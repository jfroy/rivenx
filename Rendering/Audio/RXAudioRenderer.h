//
//	RXAudioRenderer.h
//	rivenx
//
//	Created by Jean-Francois Roy on 15/02/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#if !defined(_RXAudioRenderer_)
#define _RXAudioRenderer_

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
	AudioRenderer() throw(CAXException);
	~AudioRenderer() throw(CAXException);
	
	// accessors to underlying graph and mixer
	inline AUGraph Graph() const throw() {return graph;}
	inline const CAAudioUnit& Mixer() const throw() {return *mixer;}
	
	// costly operation to prime the graph for rendering
	void Initialize() throw(CAXException);
	bool IsInitialized() const throw(CAXException);
	
	// rendering control
	void Start() throw(CAXException);
	void Stop() throw(CAXException);
	bool IsRunning() const throw(CAXException);
	
	// gain control on the final mix going to the output device
	Float32 Gain() const throw(CAXException);
	void SetGain(Float32 gain) throw(CAXException);
	
	// graph management
	inline bool AutomaticGraphUpdates() const throw() {return _automaticGraphUpdates;}
	void SetAutomaticGraphUpdates(bool b) throw();
	
	inline uint32_t AvailableMixerBusCount() const throw() {return sourceLimit - sourceCount;}
	
	// source management
	bool AttachSource(AudioSourceBase& source) throw (CAXException);
	void DetachSource(AudioSourceBase& source) throw (CAXException);
	
	UInt32 AttachSources(CFArrayRef sources) throw (CAXException);
	void DetachSources(CFArrayRef sources) throw (CAXException);
	
	// source parameter
	Float32 SourceGain(AudioSourceBase& source) const throw(CAXException);
	Float32 SourcePan(AudioSourceBase& source) const throw(CAXException);
	
	void SetSourceGain(AudioSourceBase& source, Float32 gain) throw(CAXException);
	void SetSourcePan(AudioSourceBase& source, Float32 pan) throw(CAXException);
	
	// source parameter ramping
	void RampSourceGain(AudioSourceBase& source, Float32 value, Float64 duration) throw(CAXException);
	void RampSourcePan(AudioSourceBase& source, Float32 value, Float64 duration) throw(CAXException);
	
	void RampSourcesGain(CFArrayRef sources, Float32 value, Float64 duration) throw(CAXException);
	void RampSourcesPan(CFArrayRef sources, Float32 value, Float64 duration) throw(CAXException);
	
	void RampSourcesGain(CFArrayRef sources, std::vector<Float32>values, std::vector<Float64>durations) throw(CAXException);
	void RampSourcesPan(CFArrayRef sources, std::vector<Float32>values, std::vector<Float64>durations) throw(CAXException);

private:
	static OSStatus MixerRenderNotifyCallback(void*							 inRefCon, 
											  AudioUnitRenderActionFlags*	 ioActionFlags, 
											  const AudioTimeStamp*			 inTimeStamp, 
											  UInt32						 inBusNumber, 
											  UInt32						 inNumberFrames, 
											  AudioBufferList*				 ioData);
	
	AudioRenderer(const AudioRenderer &c);
	AudioRenderer& operator=(const AudioRenderer& c) {return *this;}
	
	void RampMixerParameter(CFArrayRef sources, AudioUnitParameterID parameter, std::vector<Float32>& values, std::vector<Float64>& durations) throw(CAXException);
	
	OSStatus MixerPreRenderNotify(const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, AudioBufferList* ioData) throw();
	OSStatus MixerPostRenderNotify(const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, AudioBufferList* ioData) throw();
	
	void CreateGraph();
	void TeardownGraph();
	bool _must_update_graph_predicate() throw(CAXException);
	
	class ParameterRampDescriptor {
	public:
		const AudioSourceBase* source;
		AudioUnitParameterEvent event;
		AudioTimeStamp start;
		AudioTimeStamp previous;
		uint64_t batch;
		
		bool operator==(const ParameterRampDescriptor& other) const {return this->event.element == other.event.element;}
	};
	
	TThreadSafeList<ParameterRampDescriptor> rampDescriptorList;
	uint64_t _currentRampBatch;
	bool _coarseRamps;
	
	AUGraph graph;
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
