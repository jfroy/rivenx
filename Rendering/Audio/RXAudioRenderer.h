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

#include "base/atomic/pc_queue.h"
#include "base/ref_counted.h"

class CAAudioUnit;

namespace rx {

// The audio renderer for Riven X.
//
// Fundamentally manages an AUGraph that outputs to the default audio device. Each element (aka bus
// or voice) has enabled, gain and pan parameters that can be set or ramped. When an element is
// not enabled, its parameter ramps are not update each render cycle and samples are not processed
// from its submitted buffers.
//
// The renderer maintains a pool of buffers for each element. To submit audio to an element, get
// a buffer, fill it with samples and submit it. The buffer format is set when an element is
// acquired. The implementation does not currently support client-allocated buffers.
//
// The engine does not support scheduling element buffers or parameter edits. In other words, there
// are no timestamps associated with buffers or edits. They are consumed or applied
// "as soon as possible", which will be at most one render cycle worth of audio frames.
//
// The engine is not bound to any thread but must not be used concurrently. The one exception to
// this rule are element buffer dequeue and enqueue operations, which are independent for each
// element. In other words, buffers can be obtained and submitted concurrently across all elements,
// but serially for a given element.
class AudioRenderer {
 public:
  using milliseconds = std::chrono::milliseconds;

  struct ParameterEdit {
    AudioUnitElement element;
    float value;
    milliseconds duration;
  };
  using ParameterEditArray = std::vector<ParameterEdit>;

  const static uint32_t ELEMENT_LIMIT{16};
  const static AudioUnitElement INVALID_ELEMENT{std::numeric_limits<AudioUnitElement>::max()};

  AudioRenderer();
  ~AudioRenderer();

  // accessors to underlying graph and mixer
  inline AUGraph Graph() const { return graph_; }
  inline const CAAudioUnit& Mixer() const { return *mixer_; }

  // Maximum number of audio frames per render cycle. Undefined until after |Initialize|.
  uint32_t MaxFramesPerCycle() const { return max_frames_per_slice_; }

  // expensive one-time initialization
  void Initialize();
  bool IsInitialized() const;

  // rendering control
  void Start();
  void Stop();
  bool IsRunning() const;

  // output gain; linear response
  float gain() const;
  void set_gain(float gain);

  // update coalescing control; affects source attach, detach and parameter edits while running
  inline bool automatic_commits() const {
    return automatic_commits_.load(std::memory_order_relaxed);
  }
  void set_automatic_commits(bool automatic_commits) {
    automatic_commits_.store(automatic_commits, std::memory_order_relaxed);
  }

  // Acquire an element and set its buffer format. Return the element or INVALID_ELEMENT on error
  // (typically this will mean there are no element lefts or the format is not valid). Any parameter
  // ramps are cancelled and the element parameters are reset to defaults. Elements are initially
  // disabled.
  AudioUnitElement AcquireElement(const AudioStreamBasicDescription& asbd);
  void ReleaseElement(AudioUnitElement element);

  // Enable or disable an element.
  bool ElementEnabled(AudioUnitElement element) const;
  void SetElementEnabled(AudioUnitElement element, bool enabled);

  // Element parameters. Values have a linear response (appropriate curves are applied internally).

  float ElementGain(AudioUnitElement element) const;
  void SetElementGain(AudioUnitElement element, float gain,
                      milliseconds duration = milliseconds{0}) {
    ScheduleGainEdits({{element, gain, duration}});
  }

  float ElementPan(AudioUnitElement element) const;
  void SetElementPan(AudioUnitElement element, float pan, milliseconds duration = milliseconds{0}) {
    SchedulePanEdits({{element, pan, duration}});
  }

  void ScheduleGainEdits(const ParameterEditArray& edits);
  void SchedulePanEdits(const ParameterEditArray& edits);

  // Element buffers.

  class Buffer : public ref_counted<Buffer> {
   public:
   private:
    Buffer(int channels, int frames);
    ~Buffer() = default;

    // Same-layout structure as AudioBufferList, except with 2 buffers.
    struct DualAudioBufferList {
      UInt32 mNumberBuffers;
      AudioBuffer mBuffers[2];
    };
  };

  scoped_refptr<Buffer> DequeueBuffer(AudioUnitElement element);
  void EnqueueBuffer(AudioUnitElement element, const scoped_refptr<Buffer>& buffer);

 private:
  using seconds_f = std::chrono::duration<double, std::chrono::seconds::period>;
  using RampArray = std::array<decltype(AudioUnitParameterEvent::eventValues.ramp), ELEMENT_LIMIT>;
  using ParameterEditQueue = atomic::FixedSinglePCQueue<ParameterEdit>;

  AudioRenderer(const AudioRenderer&) = delete;
  AudioRenderer& operator=(const AudioRenderer&) = delete;

  OSStatus MixerPreRenderNotify(const AudioTimeStamp* in_timestamp, uint32_t in_bus,
                                uint32_t in_frames, AudioBufferList* io_data);
  void ApplyEdits(const AudioTimeStamp& timestamp, uint32_t in_frames,
                  AudioUnitParameterID parameter, typename ParameterEditQueue::range_pair rp,
                  RampArray& ramps);
  void ApplyRamps(const AudioTimeStamp& timestamp, uint32_t in_frames,
                  AudioUnitParameterID parameter, RampArray& ramps);

  void CreateGraph();
  void DestroyGraph();

  template <typename Transform>
  void ScheduleEdits(const ParameterEditArray& edits, ParameterEditQueue& edits_queue);

  static OSStatus MixerRenderNotifyCallback(void* in_renderer,
                                            AudioUnitRenderActionFlags* inout_action_flags,
                                            const AudioTimeStamp* in_timestamp, uint32_t in_bus,
                                            uint32_t in_frames, AudioBufferList* io_data);

  AUGraph graph_{nullptr};
  std::unique_ptr<CAAudioUnit> output_{nullptr};
  std::unique_ptr<CAAudioUnit> mixer_{nullptr};
  uint32_t max_frames_per_slice_{0};

  std::array<AUNode, ELEMENT_LIMIT> converters_;
  std::bitset<ELEMENT_LIMIT> element_allocations_;
  std::bitset<ELEMENT_LIMIT> element_enabled_;

  RampArray gain_ramps_;
  RampArray pan_ramps_;

  ParameterEditQueue pending_gain_edits_;
  ParameterEditQueue pending_pan_edits_;

  std::atomic<bool> automatic_commits_{true};
  std::atomic<int32_t> graph_updates_requested_{0};
};

}  // namespace rx {
