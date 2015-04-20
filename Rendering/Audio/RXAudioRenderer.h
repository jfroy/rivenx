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

class CAAudioUnit;

namespace rx {

// The audio engine for Riven X.
//
// Fundamentally manages an AUGraph that outputs to the default audio device. Each element (aka bus
// or voice) has enabled, gain and pan parameters that can be set or ramped. When an element is
// not enabled, its parameter ramps are not update each render cycle and samples are not processed
// from its submitted buffers.
//
// The renderer maintains a pool of buffers for each element. To submit audio to an element, get
// a buffer, fill it with samples and submit it. The buffer format is set when an element is
// acquired.
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

  AudioRenderer() noexcept;
  ~AudioRenderer() noexcept;

  // accessors to underlying graph and mixer
  inline AUGraph Graph() const noexcept { return graph_; }
  inline const CAAudioUnit& Mixer() const noexcept { return *mixer_; }

  // Maximum number of audio frames per render cycle. Undefined until after |Initialize|.
  uint32_t MaxFramesPerCycle() const noexcept { return max_frames_per_slice_; }

  // expensive one-time initialization
  void Initialize() noexcept;
  bool IsInitialized() const noexcept;

  // rendering control
  void Start() noexcept;
  void Stop() noexcept;
  bool IsRunning() const noexcept;

  // output gain; linear response
  float gain() const noexcept;
  void set_gain(float gain) noexcept;

  // update coalescing control; affects source attach, detach and parameter edits while running
  inline bool automatic_commits() const noexcept {
    return automatic_commits_.load(std::memory_order_relaxed);
  }
  void set_automatic_commits(bool automatic_commits) noexcept {
    automatic_commits_.store(automatic_commits, std::memory_order_relaxed);
  }

  // Acquire an element and set its buffer format. Return the element or INVALID_ELEMENT on error
  // (typically this will mean there are no element lefts or the format is not valid). Any parameter
  // ramps are cancelled and the element parameters are reset to defaults.
  AudioUnitElement AcquireElement(const AudioStreamBasicDescription& asbd) noexcept;
  void ReleaseElement(AudioUnitElement element) noexcept;

  // Element parameters. Values have a linear response (appropriate curves are applied internally).

  float ElementGain(AudioUnitElement element) const noexcept;
  void SetElementGain(AudioUnitElement element, float gain,
                      milliseconds duration = milliseconds{0}) noexcept {
    ScheduleGainEdits({{element, gain, duration}});
  }

  float ElementPan(AudioUnitElement element) const noexcept;
  void SetElementPan(AudioUnitElement element, float pan,
                     milliseconds duration = milliseconds{0}) noexcept {
    SchedulePanEdits({{element, pan, duration}});
  }

  void ScheduleGainEdits(const ParameterEditArray& edits) noexcept;
  void SchedulePanEdits(const ParameterEditArray& edits) noexcept;

 private:
  using seconds_f = std::chrono::duration<double, std::chrono::seconds::period>;
  using RampArray = std::array<decltype(AudioUnitParameterEvent::eventValues.ramp), ELEMENT_LIMIT>;
  using ParameterEditQueue = atomic::FixedSinglePCQueue<ParameterEdit>;

  AudioRenderer(const AudioRenderer&) = delete;
  AudioRenderer& operator=(const AudioRenderer&) = delete;

  OSStatus MixerPreRenderNotify(const AudioTimeStamp* in_timestamp, uint32_t in_bus,
                                uint32_t in_frames, AudioBufferList* io_data) noexcept;
  void ApplyEdits(const AudioTimeStamp& timestamp, uint32_t in_frames,
                  AudioUnitParameterID parameter, typename ParameterEditQueue::range_pair rp,
                  RampArray& ramps) noexcept;
  void ApplyRamps(const AudioTimeStamp& timestamp, uint32_t in_frames,
                  AudioUnitParameterID parameter, RampArray& ramps) noexcept;

  void CreateGraph() noexcept;
  void DestroyGraph() noexcept;

  template <typename Transform>
  void ScheduleEdits(const ParameterEditArray& edits, ParameterEditQueue& edits_queue) noexcept;

  static OSStatus MixerRenderNotifyCallback(void* in_renderer,
                                            AudioUnitRenderActionFlags* inout_action_flags,
                                            const AudioTimeStamp* in_timestamp, uint32_t in_bus,
                                            uint32_t in_frames, AudioBufferList* io_data) noexcept;

  AUGraph graph_{nullptr};
  std::unique_ptr<CAAudioUnit> output_{nullptr};
  std::unique_ptr<CAAudioUnit> mixer_{nullptr};
  uint32_t max_frames_per_slice_{0};

  std::array<AUNode, ELEMENT_LIMIT> converters_;
  std::bitset<ELEMENT_LIMIT> element_allocations_;

  RampArray gain_ramps_;
  RampArray pan_ramps_;

  ParameterEditQueue pending_gain_edits_;
  ParameterEditQueue pending_pan_edits_;

  std::atomic<bool> automatic_commits_{true};
  std::atomic<int32_t> graph_updates_requested_{0};
};

}  // namespace rx {
