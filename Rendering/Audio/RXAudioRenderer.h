// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include <array>
#include <atomic>
#include <bitset>
#include <chrono>
#include <memory>
#include <vector>

#include <AudioToolbox/AudioToolbox.h>

#include "base/atomic/spc_queue.h"

class CAAudioUnit;

namespace rx {

// The audio renderer for Riven X.
//
// Fundamentally manages an AUGraph that outputs to the default audio device. Each element (aka bus
// or voice) has enabled, gain and pan parameters that can be set or ramped. When an element is
// not enabled, its parameter ramps are not updated and its buffer queue is not drained as they
// normally would each render cycle.
//
// The renderer defines a Buffer type as the interface to let clients submit audio samples to an
// element. It is basically a copy of AudioBufferList but with an AudioBuffer array of capacity 2.
// Clients are expected to subclass the Buffer type to manage the lifetime of the memory referenced
// by the AudioBuffers.
//
// The engine does not support scheduling element buffers or parameter edits. In other words, there
// are no timestamps associated with buffers or edits. They are consumed or applied
// "as soon as possible", which will be at most one render cycle worth of audio frames.
//
// The engine is not bound to any thread but must not be used concurrently. The one exception to
// this rule are buffer enqueue operations, which are independent for each element. In other words,
// buffers can be submitted concurrently across elements, but serially for a given element.
//
// Element state changes, such as gain, pan and enable, are enqueued and deferred until
// SubmitElementEdits is called. This allows efficient and synchronized editing of element
// parameters.
class AudioRenderer : public noncopyable {
 public:
  using milliseconds = std::chrono::milliseconds;

  // Basic audio buffer structure. Like AudioBufferList but with 2 buffers. Clients are expected to
  // subclass this structure to manage the memory referenced by the buffer.
  struct Buffer {
    UInt32 mNumberBuffers;
    AudioBuffer mBuffers[2];
  };

  const static uint32_t ELEMENT_LIMIT{16};
  const static AudioUnitElement INVALID_ELEMENT{std::numeric_limits<AudioUnitElement>::max()};

  AudioRenderer();
  ~AudioRenderer();

  // Maximum number of audio frames per render cycle. Undefined until after |Initialize|. Audio
  // buffers should contain this number of frames for optimal performance and latency.
  uint32_t max_frames_per_cycle() const { return max_frames_per_cycle_; }

  // Performs one-time initialization.
  void Initialize();
  bool IsInitialized() const;

  // Starts or stops audio rendering.
  void Start();
  void Stop();
  bool IsRunning() const;

  // Gets or sets the master output gain. Uses a linear response curve.
  float gain() const;
  void set_gain(float gain);

  // Acquires an element and set its buffer format. Returns the element or INVALID_ELEMENT on error
  // (typically this will mean there are no element left or the format is not valid). Cancels any
  // parameter edits and resets element parameters to defaults. Elements are initially disabled.
  AudioUnitElement AcquireElement(const AudioStreamBasicDescription& asbd);
  void ReleaseElement(AudioUnitElement element);

  // Element parameters. Floating point parameters have a linear response curve.

  bool ElementEnabled(AudioUnitElement element) const;
  void SetElementEnabled(AudioUnitElement element, bool enabled);

  float ElementGain(AudioUnitElement element) const;
  void SetElementGain(AudioUnitElement element, float gain, milliseconds duration);

  float ElementPan(AudioUnitElement element) const;
  void SetElementPan(AudioUnitElement element, float pan, milliseconds duration);

  // Submits element parameter edits.
  void SubmitParameterEdits();

  // Enqueues an audio buffer for playback on a given element. Returns true if the buffer was
  // enqueued or false if the buffer was dropped.
  //
  // The renderer takes ownernship of the buffer and will destroy it once it has been rendered.
  //
  // The renderer has a limited-space queue for buffers and will start dropping buffers if it is
  // unable to drain this queue fast enough.
  bool EnqueueBuffer(AudioUnitElement element, std::unique_ptr<Buffer> buffer);

 private:
  using Ramp = decltype(AudioUnitParameterEvent::eventValues.ramp);
  using RampArray = std::array<Ramp, ELEMENT_LIMIT>;

  struct ParameterAttributes {
    std::array<float, ELEMENT_LIMIT> values;
    std::array<milliseconds, ELEMENT_LIMIT> durations;
    std::array<bool, ELEMENT_LIMIT> written;
  };

  struct ParameterBuffer {
    ParameterAttributes gain;
    ParameterAttributes pan;
    ParameterAttributes enable;
  };
  using ParameterBufferQueue = atomic::SPCQueue<std::unique_ptr<ParameterBuffer>>;

  void UpdateParameter(const AudioTimeStamp& timestamp, AudioUnitParameterID parameter,
                       const ParameterAttributes& attributes, RampArray& ramps);
  void ApplyRamps(const AudioTimeStamp& timestamp, uint32_t in_frames,
                  AudioUnitParameterID parameter, RampArray& ramps);

  void InitializeAudioGraph();
  void DestroyAudioGraph();

  static OSStatus MixerRenderNotifyCallback(void* in_renderer,
                                            AudioUnitRenderActionFlags* inout_action_flags,
                                            const AudioTimeStamp* in_timestamp, uint32_t in_bus,
                                            uint32_t in_frames, AudioBufferList* io_data);
  OSStatus MixerPreRenderNotify(const AudioTimeStamp* in_timestamp, uint32_t in_bus,
                                uint32_t in_frames, AudioBufferList* io_data);

  AUGraph graph_{nullptr};
  std::unique_ptr<CAAudioUnit> output_{nullptr};
  std::unique_ptr<CAAudioUnit> mixer_{nullptr};
  uint32_t max_frames_per_cycle_;
  milliseconds cycle_duration_;

  std::array<AUNode, ELEMENT_LIMIT> converters_;
  std::bitset<ELEMENT_LIMIT> element_allocations_;
  std::bitset<ELEMENT_LIMIT> element_enabled_;

  RampArray gain_ramps_;
  RampArray pan_ramps_;

  std::unique_ptr<ParameterBuffer> parameter_buffer_;
  ParameterBufferQueue pending_parameter_buffers_;

  using BufferQueue = atomic::SPCQueue<std::unique_ptr<Buffer>>;
  std::array<BufferQueue, ELEMENT_LIMIT> pending_buffers_;
  std::array<std::unique_ptr<Buffer>, ELEMENT_LIMIT> active_buffers_;

  std::atomic<int32_t> graph_updates_requested_{0};
};

}  // namespace rx {
