// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#include "Rendering/Audio/RXAudioRenderer.h"

#include <algorithm>
#include <cmath>
#include <thread>

#include "Base/RXLogging.h"
#include "Base/RXBufferMacros.h"
#include "Rendering/Audio/PublicUtility/CAAudioUnit.h"
#include "Rendering/Audio/PublicUtility/CAComponentDescription.h"
#include "Rendering/Audio/PublicUtility/CAXException.h"
#include "Utilities/math.h"

namespace {

using seconds_f = std::chrono::duration<float, std::chrono::seconds::period>;

struct GainTransform {
  // kAudioUnitParameterUnit_MixerFaderCurve1
  static float In(float v) { return rx::clamp(0.0f, 1.0f, cbrtf(v)); }
  static float Out(float v) { return powf(v, 3.0f); }
};

struct PanTransform {
  static float In(float v) { return rx::clamp(-1.0f, 1.0f, v); }
  static float Out(float v) { return v; }
};

struct EnableTransform {
  static float In(bool v) { return v ? 1.0f : 0.0f; }
  static bool Out(float v) { return v == 1.0f; }
};

const auto kOutputChannels = 2;

OSStatus SilenceRenderCallback(void* in_renderer, AudioUnitRenderActionFlags* inout_action_flags,
                               const AudioTimeStamp* in_timestamp, uint32_t in_bus,
                               uint32_t in_frames, AudioBufferList* io_data) {
  for (uint32_t i = 0; i < io_data->mNumberBuffers; ++i) {
    bzero(io_data->mBuffers[i].mData, io_data->mBuffers[i].mDataByteSize);
  }
  *inout_action_flags |= kAudioUnitRenderAction_OutputIsSilence;
  return noErr;
}

}  // namespace

namespace rx {

// static
constexpr AudioUnitElement AudioRenderer::INVALID_ELEMENT;
constexpr uint32_t AudioRenderer::ELEMENT_LIMIT;

AudioRenderer::AudioRenderer() {}

AudioRenderer::~AudioRenderer() {
  Stop();
  DestroyAudioGraph();
}

void AudioRenderer::Initialize() {
  InitializeAudioGraph();
  for (auto& queue : pending_buffers_) {
    queue.Resize(128);
  }
  pending_parameter_buffers_.Resize(128);
  parameter_buffer_ = std::make_unique<ParameterBuffer>();
}

bool AudioRenderer::IsInitialized() const {
  Boolean isInitialized = false;
  AUGraphIsInitialized(graph_, &isInitialized);
  return static_cast<bool>(isInitialized);
}

void AudioRenderer::Start() { AUGraphStart(graph_); }

void AudioRenderer::Stop() { AUGraphStop(graph_); }

bool AudioRenderer::IsRunning() const {
  Boolean is_running = false;
  AUGraphIsRunning(graph_, &is_running);
  return static_cast<bool>(is_running);
}

float AudioRenderer::gain() const {
  float gain;
  AudioUnitGetParameter(*mixer_, kStereoMixerParam_Volume, kAudioUnitScope_Output, 0, &gain);
  return GainTransform::Out(gain);
}

void AudioRenderer::set_gain(float gain) {
  AudioUnitSetParameter(*mixer_, kStereoMixerParam_Volume, kAudioUnitScope_Output, 0,
                        GainTransform::In(gain), 0);
}

AudioUnitElement AudioRenderer::AcquireElement(const AudioStreamBasicDescription& asbd) {
  // If the source format not mixable, bail for this source.
  CAStreamBasicDescription format(asbd);
  if (!format.IsPCM()) {
    RXCFLog(kRXLoggingAudio, kRXLoggingLevelError,
            CFSTR("AudioRenderer::AcquireElement: Requested format is not mixable."));
    return INVALID_ELEMENT;
  }

  // Only mono and stereo formats are supported. The renderer interface doesn't provide for complex
  // channel mappings.
  auto channels = format.NumberChannels();
  if (channels > 2) {
    RXCFLog(kRXLoggingAudio, kRXLoggingLevelError,
            CFSTR("AudioRenderer::AcquireElement: Requested format has more than 2 channels."));
    return INVALID_ELEMENT;
  }

  // Find an available element.
  AudioUnitElement element = 0;
  for (; element < ELEMENT_LIMIT; ++element) {
    if (!element_allocations_[element]) {
      break;
    }
  }
  if (element == element_allocations_.size()) {
    RXCFLog(kRXLoggingAudio, kRXLoggingLevelError,
            CFSTR("AudioRenderer::AcquireElement: No available element."));
    return INVALID_ELEMENT;
  }

  // Cancel all parameter ramps.
  // FIXME: implement

  // Drain all pending buffers.
  // FIXME: implement

  // Set parameters to default values.
  //  SetElementGain(element, 1.0f, milliseconds(0));
  //  SetElementPan(element, 0.5f, milliseconds(0));
  //  SetElementEnabled(element, false);
  //  SubmitParameterEdits();
  AudioUnitSetParameter(*mixer_, kStereoMixerParam_Volume, kAudioUnitScope_Input, element, 1.0f, 0);
  AudioUnitSetParameter(*mixer_, kStereoMixerParam_Pan, kAudioUnitScope_Input, element, 0.5f, 0);
  element_enabled_[element] = false;

  // Create a converter if the buffer format does not match the mixer input format. Otherwise,
  // connect the mixer directly to the render callback.
  CAStreamBasicDescription mixer_format;
  mixer_->GetFormat(kAudioUnitScope_Output, 0, mixer_format);

  if (mixer_format != format) {
    AudioComponentDescription acd;
    acd.componentType = kAudioUnitType_FormatConverter;
    acd.componentSubType = kAudioUnitSubType_AUConverter;
    acd.componentManufacturer = kAudioUnitManufacturer_Apple;
    acd.componentFlags = 0;
    acd.componentFlagsMask = 0;

    AUNode converter_node;
    AudioUnit converter_au;
    AUGraphAddNode(graph_, &acd, &converter_node);
    AUGraphNodeInfo(graph_, converter_node, nullptr, &converter_au);
    CAAudioUnit converter(converter_node, converter_au);

    converter.SetFormat(kAudioUnitScope_Input, 0, format);
    converter.SetFormat(kAudioUnitScope_Output, 0, mixer_format);

    // If the buffer format only has one channel, set a channel map to replicate it.
    if (channels == 1) {
      SInt32 channel_map[2] = {0, 0};
      converter.SetProperty(kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Global, 0,
                            channel_map, sizeof(channel_map));
    }

    // Set the render callback on the converter.
    AURenderCallbackStruct render_callback = {&ElementRenderCallback, nullptr};
    converter.SetProperty(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                          &render_callback, sizeof(render_callback));

    // Connect the converter.
    AUGraphConnectNodeInput(graph_, converter_node, 0, *mixer_, element);

    // Keep track of the converter node so we can deconnect it.
    element_converters_[element] = converter_node;
  } else {
    // Set the render callback on the mixer input element.
    AURenderCallbackStruct render_callback = {&ElementRenderCallback, nullptr};
    mixer_->SetProperty(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, element,
                        &render_callback, sizeof(render_callback));
  }

  // Store the buffer format.
  element_formats_[element] = format;

  // The element was acquired successfully.
  element_allocations_[element] = true;

  // Node connections require a graph update.
  graph_updates_requested_.fetch_add(1, std::memory_order_relaxed);

  return element;
}

void AudioRenderer::ReleaseElement(AudioUnitElement element) {
  debug_assert(element < ELEMENT_LIMIT);

  if (!element_allocations_[element]) {
#if defined(DEBUG_AUDIO)
    RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug,
            CFSTR("<rx::AudioRenderer: 0x%x> Tried to release unacquired element %u."), this,
            element);
#endif
    return;
  }

  // If this element has a converter, disconnect and remove it from the graph.
  if (element_converters_[element] != static_cast<AUNode>(0)) {
    AUGraphDisconnectNodeInput(graph_, *mixer_, element);
    AUGraphRemoveNode(graph_, element_converters_[element]);
    element_converters_[element] = static_cast<AUNode>(0);
  }

  // Set the silence render callback on the mixer element.
  AURenderCallbackStruct silence_render = {&SilenceRenderCallback, nullptr};
  mixer_->SetProperty(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, element,
                      &silence_render, sizeof(AURenderCallbackStruct));

  // Cancel all parameter ramps.
  // FIXME: implement

  // Reset element state.
  element_enabled_[element] = false;
  element_allocations_[element] = false;

  // Node disconnections require a graph update.
  graph_updates_requested_.fetch_add(1, std::memory_order_relaxed);
}

bool AudioRenderer::ElementEnabled(AudioUnitElement element) const {
  return element_enabled_[element];
}

void AudioRenderer::SetElementEnabled(AudioUnitElement element, bool enabled) {
  auto& attributes = parameter_buffer_->enable;
  attributes.values[element] = EnableTransform::In(enabled);
  attributes.durations[element] = milliseconds{0};
  attributes.written[element] = true;
}

float AudioRenderer::ElementGain(AudioUnitElement element) const {
  float gain;
  mixer_->GetParameter(kStereoMixerParam_Volume, kAudioUnitScope_Input, element, gain);
  return GainTransform::Out(gain);
}

void AudioRenderer::SetElementGain(AudioUnitElement element, float gain, milliseconds duration) {
  auto& attributes = parameter_buffer_->gain;
  attributes.values[element] = GainTransform::In(gain);
  attributes.durations[element] = milliseconds{0};
  attributes.written[element] = true;
}

float AudioRenderer::ElementPan(AudioUnitElement element) const {
  float pan;
  mixer_->GetParameter(kStereoMixerParam_Pan, kAudioUnitScope_Input, element, pan);
  return PanTransform::Out(pan);
}

void AudioRenderer::SetElementPan(AudioUnitElement element, float pan, milliseconds duration) {
  auto& attributes = parameter_buffer_->pan;
  attributes.values[element] = PanTransform::In(pan);
  attributes.durations[element] = milliseconds{0};
  attributes.written[element] = true;
}

void AudioRenderer::SubmitParameterEdits() {
  if (pending_parameter_buffers_.TryEnqueue(std::move(parameter_buffer_))) {
    parameter_buffer_ = std::make_unique<ParameterBuffer>();
  }
}

bool AudioRenderer::EnqueueBuffer(AudioUnitElement element, std::unique_ptr<Buffer> buffer) {
  auto& buffer_queue = pending_buffers_[element];
  return buffer_queue.TryEnqueue(std::move(buffer));
}

#pragma mark -

// static
OSStatus AudioRenderer::MixerRenderNotifyCallback(void* in_renderer,
                                                  AudioUnitRenderActionFlags* inout_action_flags,
                                                  const AudioTimeStamp* in_timestamp,
                                                  uint32_t in_bus, uint32_t in_frames,
                                                  AudioBufferList* io_data) {
  auto renderer = reinterpret_cast<rx::AudioRenderer*>(in_renderer);
  if (*inout_action_flags & kAudioUnitRenderAction_PreRender) {
    renderer->MixerPreRenderNotify(in_timestamp, in_bus, in_frames, io_data);
  }
  return noErr;
}

void AudioRenderer::MixerPreRenderNotify(const AudioTimeStamp* in_timestamp, uint32_t in_bus,
                                         uint32_t in_frames, AudioBufferList* io_data) {
  // Finalize graph updates if needed.
  int32_t graph_updates = graph_updates_requested_.load(std::memory_order_relaxed);
  if (graph_updates > 0) {
    AUGraphUpdate(graph_, nullptr);
    graph_updates_requested_.fetch_sub(graph_updates, std::memory_order_relaxed);
  }

  // Merge all pending parameter buffers into one.
  auto range = pending_parameter_buffers_.DequeueRange();
  if (!range.empty()) {
    ParameterBuffer parameter_buffer;
    for (const auto& buffer : range) {
      for (uint32_t i = 0; i < ELEMENT_LIMIT; ++i) {
        if (buffer->gain.written[i]) {
          parameter_buffer.gain.values[i] = buffer->gain.values[i];
        }
      }
      for (uint32_t i = 0; i < ELEMENT_LIMIT; ++i) {
        if (buffer->pan.written[i]) {
          parameter_buffer.pan.values[i] = buffer->pan.values[i];
        }
      }
      for (uint32_t i = 0; i < ELEMENT_LIMIT; ++i) {
        if (buffer->enable.written[i]) {
          parameter_buffer.enable.values[i] = buffer->enable.values[i];
        }
      }
    }

    // Process the merged parameter buffer.
    for (uint32_t i = 0; i < ELEMENT_LIMIT; ++i) {
      if (parameter_buffer.enable.written[i]) {
        element_enabled_[i] = EnableTransform::Out(parameter_buffer.enable.values[i]);
      }
    }
    UpdateParameter(*in_timestamp, kStereoMixerParam_Volume, parameter_buffer.gain, gain_ramps_);
    UpdateParameter(*in_timestamp, kStereoMixerParam_Pan, parameter_buffer.pan, pan_ramps_);

    pending_parameter_buffers_.Consume(range);
  }

  // Apply ramps.
  ApplyRamps(*in_timestamp, in_frames, kStereoMixerParam_Volume, gain_ramps_);
  ApplyRamps(*in_timestamp, in_frames, kStereoMixerParam_Pan, pan_ramps_);
}

void AudioRenderer::UpdateParameter(const AudioTimeStamp& timestamp, AudioUnitParameterID parameter,
                                    const ParameterAttributes& attributes, RampArray& ramps) {
  // Create a parameter event for immediate attributes. The events are stored in |events| and
  // indexed by their element using |events_by_element| (allowing for unwritten attributes). Once
  // all events have been created, they are applied together using |AudioUnitScheduleParameters|.
  //
  // For attributes with a duration, the parameter ramp is updated.

  std::array<AudioUnitParameterEvent, ELEMENT_LIMIT> events;
  std::array<uint32_t, ELEMENT_LIMIT> events_by_element;
  events_by_element.fill(ELEMENT_LIMIT);
  uint32_t event_count = 0;

  for (uint32_t element = 0; element < ELEMENT_LIMIT; ++element) {
    auto& ramp = ramps[element];

    // If the duration is zero, reset the ramp and prepare an immediate parameter event.
    if (attributes.durations[element].count() == 0) {
      // Reset the ramp for this element.
      ramp.startBufferOffset = 0;
      ramp.durationInFrames = 0;
      ramp.startValue = ramp.endValue = attributes.values[element];

      // Lookup the parameter event index for the element. Assign a new index if needed.
      auto event_index = events_by_element[element];
      if (event_index == ELEMENT_LIMIT) {
        event_index = event_count++;
        events_by_element[element] = event_index;
      }

      // Update the event.
      auto& event = events[event_index];
      event.scope = kAudioUnitScope_Input;
      event.element = element;
      event.parameter = parameter;
      event.eventType = kParameterEvent_Immediate;
      event.eventValues.immediate.bufferOffset = 0;
      event.eventValues.immediate.value = attributes.values[element];
    } else {
      // Update the parameter ramp.
      //
      // * |startBufferOffset| is reset to 0 (it indicates the progress of the ramp in frames).
      // * |durationInFrames| is set to the ramp duration in frames derived from the attribure
      //   duration in seconds.
      // * |startValue| is left alone. It stores the current value of the ramp. Updating a ramp only
      //   changes the end value and duration.
      // * |endValue| is set to the delta between the ramp's end value and start value.
      double sample_rate;
      mixer_->GetSampleRate(kAudioUnitScope_Input, element, sample_rate);
      auto seconds = std::chrono::duration_cast<seconds_f>(attributes.durations[element]).count();

      ramp.startBufferOffset = 0;
      ramp.durationInFrames = static_cast<uint32_t>(std::ceil(seconds * sample_rate));
      ramp.endValue = attributes.values[element] - ramp.startValue;
    }
  }

  // Schedule the events.
  AudioUnitScheduleParameters(*mixer_, events.data(), event_count);
}

void AudioRenderer::ApplyRamps(const AudioTimeStamp& timestamp, uint32_t in_frames,
                               AudioUnitParameterID parameter, RampArray& ramps) {
  // Create a parameter ramp event for each ramp. The events are stored in |events| (in element
  // order) and indexed by their element in |events_by_element|. Onces all events have been created,
  // they are applied all at once using |AudioUnitScheduleParameters|.
  //
  // Note that the parameter ramp event applies to this render cycle only, whereas the ramps stored
  // in |ramps| represent the persistent state of active parameter ramps and are used from one
  // render cycle to the next.

  std::array<AudioUnitParameterEvent, ELEMENT_LIMIT> events;
  std::array<uint32_t, ELEMENT_LIMIT> events_by_element;
  events_by_element.fill(ELEMENT_LIMIT);
  uint32_t event_count = 0;

  for (uint32_t element = 0; element < ELEMENT_LIMIT; ++element) {
    auto& ramp = ramps[element];

    // If there is no ramp for this element, move on to the next.
    if (ramp.durationInFrames == 0) {
      continue;
    }

    // If the element is disabled, don't process or update the ramp.
    if (!element_enabled_[element]) {
      continue;
    }

    // Calculate the number of frames left for the ramp. If zero, update the ramp's duration to mark
    // it as done and move on to the next.
    auto frames_left = ramp.durationInFrames - ramp.startBufferOffset;
    if (frames_left == 0) {
      ramp.durationInFrames = 0;
      continue;
    }

    // Lookup the parameter event index for the element. Assign a new index if needed.
    auto event_index = events_by_element[element];
    if (event_index == ELEMENT_LIMIT) {
      event_index = event_count++;
      events_by_element[element] = event_index;
    }

    // Update the ramp event.
    //
    // * |startBufferOffset| is set to 0 (there is no support to start a ramp inside a buffer
    //   rather than at the beginning of a buffer).
    // * |durationInFrames| is set to the minimum of the frame count for the render cycle and the
    //   number of ramp frames left.
    // * |startValue| is set to the current value of the ramp.
    // * |endValue| is set to the final value of the ramp for this render cycle by linearly
    //   interpolating from |startValue| by the duration of the ramp weighed by the number of frames
    //   for this render cycle.
    auto& event = events[event_index];
    event.scope = kAudioUnitScope_Input;
    event.element = element;
    event.parameter = parameter;
    event.eventType = kParameterEvent_Ramped;
    event.eventValues.ramp.startBufferOffset = 0;
    event.eventValues.ramp.durationInFrames = std::min(in_frames, frames_left);
    event.eventValues.ramp.startValue = ramp.startValue;
    event.eventValues.ramp.endValue =
        ramp.startValue +
        (static_cast<float>(event.eventValues.ramp.durationInFrames) / ramp.durationInFrames) *
            ramp.endValue;

    // Update the progress of the ramp by adding the number of frames for this render cycle to
    // |startBufferOffset| and setting |startValue| to the final value of the ramp for this render
    // cycle.
    ramp.startBufferOffset += event.eventValues.ramp.durationInFrames;
    ramp.startValue = event.eventValues.ramp.endValue;
  }

  // Schedule the events.
  AudioUnitScheduleParameters(*mixer_, events.data(), event_count);
}

// static
OSStatus AudioRenderer::ElementRenderCallback(void* in_renderer,
                                              AudioUnitRenderActionFlags* inout_action_flags,
                                              const AudioTimeStamp* in_timestamp, uint32_t in_bus,
                                              uint32_t in_frames, AudioBufferList* io_data) {
  auto renderer = reinterpret_cast<rx::AudioRenderer*>(in_renderer);
  renderer->Render(in_timestamp, in_bus, in_frames, inout_action_flags, io_data);
  return noErr;
}

void AudioRenderer::Render(const AudioTimeStamp* in_timestamp, uint32_t in_bus, uint32_t in_frames,
                           AudioUnitRenderActionFlags* out_action_flags, AudioBufferList* io_data) {
  const uint32_t frame_bytes = element_formats_[in_bus].FramesToBytes(in_frames);
  for (uint32_t i = 0; i < io_data->mNumberBuffers; ++i) {
    debug_assert(io_data->mBuffers[i].mDataByteSize <= frame_bytes);
  }

  uint32_t input_offset = 0;
  while (input_offset < frame_bytes) {
    // Dequeue a buffer for the element if needed.
    if (!active_buffers_[in_bus]) {
      auto range = pending_buffers_[in_bus].DequeueRange();

      // If there are no pending buffers, fill the rest of the buffer with silence.
      if (range.empty()) {
        for (uint32_t i = 0; i < io_data->mNumberBuffers; ++i) {
          bzero(BUFFER_OFFSET(active_buffers_[in_bus]->mBuffers[i].mData,
                              active_buffer_offsets_[in_bus]),
                frame_bytes - input_offset);
        }
        return;
      }

      // Consume the next pending buffer.
      active_buffers_[in_bus] = std::move(*std::begin(range));
      pending_buffers_[in_bus].Consume(std::begin(range), std::begin(range) + 1);
      active_buffer_offsets_[in_bus] = 0;

      debug_assert(io_data->mNumberBuffers == active_buffers_[in_bus]->mNumberBuffers);
      for (uint32_t i = 0; i < active_buffers_[in_bus]->mNumberBuffers; ++i) {
        debug_assert(active_buffers_[in_bus]->mBuffers[i].mNumberChannels ==
                     io_data->mBuffers[i].mNumberChannels);
        debug_assert(active_buffers_[in_bus]->mBuffers[i].mDataByteSize ==
                     active_buffers_[in_bus]->mBuffers[0].mDataByteSize);
      }
    }

    // Copy as many bytes as needed or possible.
    auto bytes =
        std::min(frame_bytes - input_offset, active_buffers_[in_bus]->mBuffers[0].mDataByteSize);
    for (uint32_t i = 0; i < io_data->mNumberBuffers; ++i) {
      memcpy(
          BUFFER_OFFSET(io_data->mBuffers[i].mData, input_offset),
          BUFFER_OFFSET(active_buffers_[in_bus]->mBuffers[i].mData, active_buffer_offsets_[in_bus]),
          bytes);
    }
    input_offset += bytes;
    active_buffer_offsets_[in_bus] += bytes;

    // Clear the active buffer if all its bytes have been copied.
    if (active_buffer_offsets_[in_bus] == active_buffers_[in_bus]->mBuffers[0].mDataByteSize) {
      active_buffers_[in_bus] = nullptr;
    }
  }
}

void AudioRenderer::InitializeAudioGraph() {
  AudioComponentDescription acd;
  acd.componentType = 0;
  acd.componentSubType = 0;
  acd.componentManufacturer = kAudioUnitManufacturer_Apple;
  acd.componentFlags = 0;
  acd.componentFlagsMask = 0;
  AudioUnit au;

  // main processing graph
  NewAUGraph(&graph_);

  // add the default output AU to the graph
  AUNode output_node;
  acd.componentType = kAudioUnitType_Output;
  acd.componentSubType = kAudioUnitSubType_DefaultOutput;
  AUGraphAddNode(graph_, &acd, &output_node);

  // add in the stereo mixer
  AUNode mixer_node;
  acd.componentType = kAudioUnitType_Mixer;
  acd.componentSubType = kAudioUnitSubType_StereoMixer;
  AUGraphAddNode(graph_, &acd, &mixer_node);

  // open the graph so that the mixer and AUHAL units are instanciated
  AUGraphOpen(graph_);

  // get the output unit
  AUGraphNodeInfo(graph_, output_node, nullptr, &au);
  output_ = std::make_unique<CAAudioUnit>(output_node, au);

  // get the mixer unit
  AUGraphNodeInfo(graph_, mixer_node, nullptr, &au);
  mixer_ = std::make_unique<CAAudioUnit>(mixer_node, au);

  // By default, use the same sampling rate as the output device but restrict to 2 channels.
  // TODO(jfroy): Track the output sampling rate.
  // TODO(jfroy): Allow client to change processing sampling rate.
  CAStreamBasicDescription format;
  output_->GetFormat(kAudioUnitScope_Output, 0, format);
  format.ChangeNumberChannels(kOutputChannels, format.IsInterleaved());

  // Set the format as the output unit's input format and mixer unit's output format.
  output_->SetFormat(kAudioUnitScope_Input, 0, format);
  mixer_->SetFormat(kAudioUnitScope_Output, 0, format);

  // add a pre-render callback on the mixer to apply parameter edits and perform graph updates
  mixer_->AddRenderNotify(&AudioRenderer::MixerRenderNotifyCallback, this);

  // connect the output unit and the mixer
  AUGraphConnectNodeInput(graph_, *mixer_, 0, output_node, 0);

  // set the maximum number of mixer inputs
  mixer_->SetProperty(kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &ELEMENT_LIMIT,
                      sizeof(ELEMENT_LIMIT));

  // query the maximum frames per render cycle that the output unit will request
  UInt32 prop_size = sizeof(max_frames_per_cycle_);
  output_->GetProperty(kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                       &max_frames_per_cycle_, &prop_size);

  // set a silence render callback on the mixer input busses
  AURenderCallbackStruct silence_render = {&SilenceRenderCallback, nullptr};
  for (AudioUnitElement element = 0; element < ELEMENT_LIMIT; ++element) {
    mixer_->SetProperty(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, element,
                        &silence_render, sizeof(AURenderCallbackStruct));
  }

  AUGraphInitialize(graph_);
}

void AudioRenderer::DestroyAudioGraph() {
  AUGraphUninitialize(graph_);
  AUGraphClose(graph_);
  DisposeAUGraph(graph_);
}

}  // namespace rx
