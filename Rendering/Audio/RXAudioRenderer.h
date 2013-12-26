//
//  RXAudioRenderer.h
//  rivenx
//
//  Created by Jean-Francois Roy on 15/02/2006.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#if !defined(_RXAudioRenderer_)
#define _RXAudioRenderer_

#include <stdint.h>
#include <vector>

#include <CoreFoundation/CoreFoundation.h>

#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AudioToolbox.h>

#include "Rendering/Audio/PublicUtility/CAAudioUnit.h"
#include "Rendering/Audio/PublicUtility/CAGuard.h"
#include "Rendering/Audio/PublicUtility/CAThreadSafeList.h"
#include "Rendering/Audio/PublicUtility/CAXException.h"

namespace RX {

class AudioSourceBase;

class AudioRenderer {
public:
  AudioRenderer() noexcept(false);
  ~AudioRenderer() noexcept(false);

  // accessors to underlying graph and mixer
  inline AUGraph Graph() const noexcept { return graph; }
  inline const CAAudioUnit& Mixer() const noexcept { return *mixer; }

  // costly operation to prime the graph for rendering
  void Initialize() noexcept(false);
  bool IsInitialized() const noexcept(false);

  // rendering control
  void Start() noexcept(false);
  void Stop() noexcept(false);
  bool IsRunning() const noexcept(false);

  // gain control on the final mix going to the output device
  Float32 Gain() const noexcept(false);
  void SetGain(Float32 gain) noexcept(false);

  // graph management
  inline bool AutomaticGraphUpdates() const noexcept { return _automaticGraphUpdates; }
  void SetAutomaticGraphUpdates(bool b) noexcept;

  inline uint32_t AvailableMixerBusCount() const noexcept { return sourceLimit - sourceCount; }

  // source management
  bool AttachSource(AudioSourceBase& source) noexcept(false);
  void DetachSource(AudioSourceBase& source) noexcept(false);

  UInt32 AttachSources(CFArrayRef sources) noexcept(false);
  void DetachSources(CFArrayRef sources) noexcept(false);

  // source parameter
  Float32 SourceGain(AudioSourceBase& source) const noexcept(false);
  Float32 SourcePan(AudioSourceBase& source) const noexcept(false);

  void SetSourceGain(AudioSourceBase& source, Float32 gain) noexcept(false);
  void SetSourcePan(AudioSourceBase& source, Float32 pan) noexcept(false);

  // source parameter ramping
  void RampSourceGain(AudioSourceBase& source, Float32 value, Float64 duration) noexcept(false);
  void RampSourcePan(AudioSourceBase& source, Float32 value, Float64 duration) noexcept(false);

  void RampSourcesGain(CFArrayRef sources, Float32 value, Float64 duration) noexcept(false);
  void RampSourcesPan(CFArrayRef sources, Float32 value, Float64 duration) noexcept(false);

  void RampSourcesGain(CFArrayRef sources, std::vector<Float32> values, std::vector<Float64> durations) noexcept(false);
  void RampSourcesPan(CFArrayRef sources, std::vector<Float32> values, std::vector<Float64> durations) noexcept(false);

private:
  static OSStatus MixerRenderNotifyCallback(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                                            UInt32 inNumberFrames, AudioBufferList* ioData);

  AudioRenderer(const AudioRenderer& c);
  AudioRenderer& operator=(const AudioRenderer& c) { return *this; }

  void RampMixerParameter(CFArrayRef sources, AudioUnitParameterID parameter_id, std::vector<Float32>& values,
                          std::vector<Float64>& durations) noexcept(false);

  OSStatus MixerPreRenderNotify(const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, AudioBufferList* ioData) noexcept;
  OSStatus MixerPostRenderNotify(const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, AudioBufferList* ioData) noexcept;

  void CreateGraph();
  void TeardownGraph();
  bool _must_update_graph_predicate() noexcept(false);

  struct ParameterRampDescriptor {
    const AudioSourceBase* source;
    AudioUnitParameterEvent event;
    AudioTimeStamp start;
    AudioTimeStamp previous;
    uint64_t generation;

    bool operator==(const ParameterRampDescriptor& other) const
    { return this->event.element == other.event.element && this->event.parameter == other.event.parameter && this->generation == other.generation; }
  };

  uint64_t pending_ramp_generation;
  TThreadSafeList<ParameterRampDescriptor> pending_ramps;
  TThreadSafeList<ParameterRampDescriptor> active_ramps;

  AUGraph graph;
  CAAudioUnit* output;
  CAAudioUnit* mixer;
  bool _automaticGraphUpdates;
  bool _graphUpdateNeeded;

  UInt32 sourceLimit;
  UInt32 sourceCount;

  std::vector<AUNode>* busNodeVector;
  std::vector<bool>* busAllocationVector;
};
}

#endif // _RXAudioRenderer
