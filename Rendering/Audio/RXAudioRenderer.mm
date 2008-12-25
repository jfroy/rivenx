//
//	RXAudioRenderer.cpp
//	rivenx
//
//	Created by Jean-Francois Roy on 15/02/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#include <algorithm>

#include <CoreFoundation/CoreFoundation.h>
#include <libkern/OSAtomic.h>

#include "RXAtomic.h"
#include "RXLogging.h"

#include "RXAudioRenderer.h"
#include "RXAudioSourceBase.h"

#if defined(RIVENX)
#include "RXWorldProtocol.h"
#endif

#import "GTMSystemVersion.h"

#include "Rendering/Audio/PublicUtility/CAComponentDescription.h"

namespace RX {

static OSStatus RXAudioRendererSilenceRenderCallback(void							*inRefCon, 
													 AudioUnitRenderActionFlags		*ioActionFlags, 
													 const AudioTimeStamp			*inTimeStamp, 
													 UInt32							inBusNumber, 
													 UInt32							inNumberFrames, 
													 AudioBufferList				*ioData)
{
	UInt32 buffer_index = 0;
	for (; buffer_index < ioData->mNumberBuffers; buffer_index++) {
		bzero(ioData->mBuffers[buffer_index].mData, ioData->mBuffers[buffer_index].mDataByteSize);
	}
	
	*ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
	return noErr;
}

static const void* AudioSourceBaseArrayRetain(CFAllocatorRef allocator, const void* value) {
	return value;
}

static void AudioSourceBaseArrayRelease(CFAllocatorRef allocator, const void* value) {

}

static CFStringRef AudioSourceBaseArrayDescription(const void* value) {
	return CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::AudioSourceBase: 0x%x>"), value);
}

static Boolean AudioSourceBaseArrayEqual(const void* value1, const void* value2) {
	return value1 == value2;
}

static CFArrayCallBacks g_weakAudioSourceBaseArrayCallbacks = {0, AudioSourceBaseArrayRetain, AudioSourceBaseArrayRelease, AudioSourceBaseArrayDescription, AudioSourceBaseArrayEqual};

#pragma mark -

OSStatus AudioRenderer::MixerRenderNotifyCallback(void							 *inRefCon, 
												  AudioUnitRenderActionFlags	 *ioActionFlags, 
												  const AudioTimeStamp			 *inTimeStamp, 
												  UInt32						 inBusNumber, 
												  UInt32						 inNumberFrames, 
												  AudioBufferList				 *ioData)
{
	RX::AudioRenderer* renderer = reinterpret_cast<RX::AudioRenderer*>(inRefCon);
	if (*ioActionFlags & kAudioUnitRenderAction_PreRender) return renderer->MixerPreRenderNotify(inTimeStamp, inNumberFrames, ioData);
	if (*ioActionFlags & kAudioUnitRenderAction_PostRender) return renderer->MixerPostRenderNotify(inTimeStamp, inNumberFrames, ioData);
	return noErr;
}

#pragma mark -

AudioRenderer::AudioRenderer() throw(CAXException) :
_currentRampBatch(0),
_coarseRamps(false),
graph(0),
mixer(0),
_automaticGraphUpdates(true),
_graphUpdateNeeded(false),
sourceLimit(0),
sourceCount(0),
busNodeVector(0),
busAllocationVector(0)
{
	CreateGraph();
	
	// always use "coarse" ramps
	_coarseRamps = true;
	
#if defined(DEBUG)
	CFStringRef rxar_debug = CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::AudioRenderer: 0x%x> {sourceLimit=%u, coarseRamps=%d}"), this, sourceLimit, _coarseRamps);
	RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, rxar_debug);
	CFRelease(rxar_debug);
#endif
}

AudioRenderer::AudioRenderer(const AudioRenderer &c) {
	
}

AudioRenderer::~AudioRenderer() throw(CAXException) {
	// FIXME: explicitly detach any attached sources
	TeardownGraph();
}

void AudioRenderer::Initialize() throw(CAXException) {
	XThrowIfError(AUGraphInitialize(graph), "AUGraphInitialize");
}

bool AudioRenderer::IsInitialized() const throw(CAXException) {
	Boolean isInitialized = false;
	XThrowIfError(AUGraphIsInitialized(graph, &isInitialized), "AUGraphIsInitialized");
	return static_cast<bool>(isInitialized);
}

void AudioRenderer::Start() throw(CAXException) {
	XThrowIfError(AUGraphStart(graph), "AUGraphStart");
}

void AudioRenderer::Stop() throw(CAXException) {
	XThrowIfError(AUGraphStop(graph), "AUGraphStop");
}

bool AudioRenderer::IsRunning() const throw(CAXException) {
	Boolean isRunning = false;
	XThrowIfError(AUGraphIsRunning(graph, &isRunning), "AUGraphIsRunning");
	return static_cast<bool>(isRunning);
}

bool AudioRenderer::_must_update_graph_predicate() throw(CAXException) {
	if (_automaticGraphUpdates) {
		_graphUpdateNeeded = false;
		return IsRunning() || IsInitialized();
	} else {
		_graphUpdateNeeded = (_graphUpdateNeeded) ? true : (IsRunning() || IsInitialized());
		return false;
	}
}

Float32 AudioRenderer::Gain() const throw(CAXException) {
	Float32 volume;
	XThrowIfError(AudioUnitGetParameter(*mixer, kStereoMixerParam_Volume, kAudioUnitScope_Output, 0, &volume), "AudioUnitGetParameter");
	return volume;
}

void AudioRenderer::SetGain(Float32 gain) throw(CAXException) {
	XThrowIfError(AudioUnitSetParameter(*mixer, kStereoMixerParam_Volume, kAudioUnitScope_Output, 0, gain, 0), "AudioUnitSetParameter");
}

void AudioRenderer::SetAutomaticGraphUpdates(bool b) throw() {
	// if we're enabling automatic updates and an update is required, do it now
	if (b && _graphUpdateNeeded) {
		// it's possible the update will fail because the graph is in-use, so spin until the graph does get updated
		OSStatus err = kAUGraphErr_CannotDoInCurrentContext;
		while (err == kAUGraphErr_CannotDoInCurrentContext) {
			err = AUGraphUpdate(graph, NULL);
			if (err != kAUGraphErr_CannotDoInCurrentContext && err != noErr) XThrowIfError(err, "AUGraphUpdate");
		}
	}
	
	// update _automaticGraphUpdates
	_automaticGraphUpdates = b;
	
	// if automatic updates are enabled, set _graphUpdateNeeded to false
	if (_automaticGraphUpdates) _graphUpdateNeeded = false;
}

bool AudioRenderer::AttachSource(AudioSourceBase& source) throw (CAXException) {
	const AudioSourceBase* sourcePointer = &source;
	CFArrayRef temp = CFArrayCreate(NULL, reinterpret_cast<const void **>(&sourcePointer), 1, NULL);
	UInt32 attached = AttachSources(temp);
	
	CFRelease(temp);
	return attached > 0;
}

void AudioRenderer::DetachSource(AudioSourceBase& source) throw (CAXException) {
	const AudioSourceBase* sourcePointer = &source;
	CFArrayRef temp = CFArrayCreate(NULL, reinterpret_cast<const void **>(&sourcePointer), 1, NULL);
	DetachSources(temp);
	CFRelease(temp);
}

UInt32 AudioRenderer::AttachSources(CFArrayRef sources) throw (CAXException) {
	XThrowIf(sources == NULL, paramErr, "AudioRenderer::AttachSources (sources == NULL)");
	UInt32 sourceIndex = 0;
	UInt32 count = CFArrayGetCount(sources);
	AudioSourceBase* source = NULL;
	
	// if anything bad happens, we'll wipe the bad source before re-throwing
	try {
		// source index also turns out to be the number of sources we attached successfully
		for (; sourceIndex < count; sourceIndex++) {
			source = const_cast<AudioSourceBase *>(reinterpret_cast<const AudioSourceBase*>(CFArrayGetValueAtIndex(sources, sourceIndex)));
			XThrowIf(source == NULL, paramErr, "AudioRenderer::AttachSources (source == NULL)");
			
			// if the source is already attached to this renderer, move on
			if (source->rendererPtr == this) continue;
			
			// if the source is already attached to a different renderer, bail for this source
			XThrowIf(source->rendererPtr != 0 && source->rendererPtr != this, paramErr, "AudioRenderer::AttachSources (source->rendererPtr != 0 && source->rendererPtr != this)");
			
			// if the mixer cannot accept more connections, bail
			if (sourceCount >= sourceLimit) break;
			
			// find the next available bus, bail if there are no more busses
			std::vector<bool>::iterator busIterator;
			busIterator = find(busAllocationVector->begin(), busAllocationVector->end(), false);
			if (busIterator == busAllocationVector->end() && busAllocationVector->size() == sourceLimit) break;
			
			// if the source format is invalid or not mixable, bail for this source
			if (!CAStreamBasicDescription::IsMixable(source->Format())) continue;
			
			// compute and set the source's bus index
			source->bus = static_cast<AudioUnitElement>(busIterator - busAllocationVector->begin());
			
			// make a new sub-graph node for the source
			AUNode graphNode;
			XThrowIfError(AUGraphNewNodeSubGraph(graph, &graphNode), "AUGraphNewNodeSubGraph");
			(*busNodeVector)[source->bus] = graphNode;
			
			// set the source's graph and add a generic output AU
			XThrowIfError(AUGraphGetNodeInfoSubGraph(graph, graphNode, &(source->graph)), "AUGraphGetNodeInfoSubGraph");
			
			AUNode ouputNode;
			AudioUnit outputAU;
			CAComponentDescription cd(kAudioUnitType_Output, kAudioUnitSubType_GenericOutput, kAudioUnitManufacturer_Apple);
			
			XThrowIfError(AUGraphNewNode(source->graph, &cd, 0, NULL, &ouputNode), "AUGraphNewNode");
			XThrowIfError(AUGraphGetNodeInfo(source->graph, ouputNode, NULL, NULL, NULL, &outputAU), "AUGraphGetNodeInfo");
			source->outputUnit = CAAudioUnit(ouputNode, outputAU);
			
			// a non-NULL renderer means the source has been attached properly
			source->rendererPtr = this;
			
			// reset the pan and gain parameters
			SetSourceGain(*source, 1.0f);
			SetSourcePan(*source, 0.5f);
			
			// ask the source to populate the graph some more
			source->PopulateGraph();
			
			// connect the souce graph to the mixer bus
			XThrowIfError(AUGraphConnectNodeInput(graph, graphNode, 0, *mixer, source->bus), "AUGraphConnectNodeInput");
			
			// account for the new connection and return
			sourceCount++;
			(*busAllocationVector)[source->bus] = true;
		}
	} catch (CAXException c) {
		// if the graph is running or initialized, we need to schedule a graph update
		if (_must_update_graph_predicate()) XThrowIfError(AUGraphUpdate(graph, NULL), "AUGraphUpdate");
		
		// if a source was being processed when the exception was thrown...
		if (source != NULL) {
			// if the sub-graph node has been created, we need to remove it
			if ((*busNodeVector)[source->bus]) {
				// if the sub-graph node has a connection, we need to disconnect it first
				UInt32 numConnections;
				if (AUGraphCountNodeConnections(graph, (*busNodeVector)[source->bus], &numConnections) == noErr) {
					AUGraphDisconnectNodeInput(graph, *mixer, source->bus);
					if (_must_update_graph_predicate()) AUGraphUpdate(graph, NULL);
				}
				
				AUGraphRemoveNode(graph, (*busNodeVector)[source->bus]);
				(*busNodeVector)[source->bus] = static_cast<AUNode>(0);
			}
			
			source->rendererPtr = 0;
			source->bus = 0;
			source->graph = reinterpret_cast<AUGraph>(NULL);
			source->outputUnit = CAAudioUnit();
		}
		
		// re-throw the exception at the caller
		throw;
	}
	
	// if the graph is running or initialized, we need to schedule a graph update
	if (_must_update_graph_predicate()) XThrowIfError(AUGraphUpdate(graph, NULL), "AUGraphUpdate");
	
	return sourceIndex;
}

void AudioRenderer::DetachSources(CFArrayRef sources) throw (CAXException) {
	XThrowIf(sources == 0, paramErr, "AudioRenderer::DetachSources");
	UInt32 count = CFArrayGetCount(sources);
	UInt32 sourceIndex = 0;
	
	AudioUnitElement* busToRecycle = new AudioUnitElement[count];
	XThrowIf(busToRecycle == 0, mFulErr, "AudioRenderer::DetachSources");
	
	for (; sourceIndex < count; sourceIndex++) {
		AudioSourceBase* source = const_cast<AudioSourceBase *>(reinterpret_cast<const AudioSourceBase*>(CFArrayGetValueAtIndex(sources, sourceIndex)));
		XThrowIf(source->rendererPtr != this, paramErr, "AudioRenderer::DetachSources");
		
		// cache the source bus
		busToRecycle[sourceIndex] = source->bus;
		
		// disconnect the sub-graph node
		XThrowIfError(AUGraphDisconnectNodeInput(graph, *mixer, busToRecycle[sourceIndex]), "AUGraphDisconnectNodeInput");
		
		// invalidate any ongoing ramp for this source
		ParameterRampDescriptor descriptor;
		descriptor.event.element = source->bus;
		rampDescriptorList.deferred_remove(descriptor);
		
		// invalidate the source's graph-related variables
		source->bus = 0;
		source->graph = reinterpret_cast<AUGraph>(0);
		source->outputUnit = CAAudioUnit();
		
		// a 0 renderer means the source is not attached
		source->rendererPtr = 0;
		
		// notify the source
		source->HandleDetach();
	}
	
	// if the graph is running or initialized, we need to schedule a graph update before we can remove the nodes
	if (_must_update_graph_predicate()) XThrowIfError(AUGraphUpdate(graph, NULL), "AUGraphUpdate");
	
	for (sourceIndex = 0; sourceIndex < count; sourceIndex++) {
		// remove the node from the graph
		XThrowIfError(AUGraphRemoveNode(graph, (*busNodeVector)[busToRecycle[sourceIndex]]), "AUGraphRemoveNode");
		
		// account for the lost connection
		sourceCount--;
		(*busAllocationVector)[busToRecycle[sourceIndex]] = false;
		(*busNodeVector)[busToRecycle[sourceIndex]] = static_cast<AUNode>(0);
	}
	
	delete[] busToRecycle;
}

Float32 AudioRenderer::SourceGain(AudioSourceBase& source) const throw(CAXException) {
	Float32 value;
	XThrowIfError(mixer->GetParameter(kStereoMixerParam_Volume, kAudioUnitScope_Input, source.bus, value), "CAAudioUnit::GetParameter");
	return value;
}

Float32 AudioRenderer::SourcePan(AudioSourceBase& source) const throw(CAXException) {
	Float32 value;
	XThrowIfError(mixer->GetParameter(kStereoMixerParam_Pan, kAudioUnitScope_Input, source.bus, value), "CAAudioUnit::GetParameter");
	return value;
}

void AudioRenderer::SetSourceGain(AudioSourceBase& source, Float32 gain) throw(CAXException) {
	XThrowIf(source.rendererPtr != this, paramErr, "AudioRenderer::SetSourceGain (source.rendererPtr != this)");
	
	// invalidate any ongoing ramp for this source
	ParameterRampDescriptor descriptor;
	descriptor.event.element = source.bus;
	rampDescriptorList.deferred_remove(descriptor);
	
	XThrowIfError(mixer->SetParameter(kStereoMixerParam_Volume, kAudioUnitScope_Input, source.bus, gain), "CAAudioUnit::SetParameter");
}

void AudioRenderer::SetSourcePan(AudioSourceBase& source, Float32 pan) throw(CAXException) {
	XThrowIf(source.rendererPtr != this, paramErr, "AudioRenderer::SetSourcePan (source.rendererPtr != this)");
	
	// invalidate any ongoing ramp for this source
	ParameterRampDescriptor descriptor;
	descriptor.event.element = source.bus;
	rampDescriptorList.deferred_remove(descriptor);
	
	XThrowIfError(mixer->SetParameter(kStereoMixerParam_Pan, kAudioUnitScope_Input, source.bus, pan), "CAAudioUnit::SetParameter");
}

void AudioRenderer::RampSourceGain(AudioSourceBase& source, Float32 value, Float64 duration) throw(CAXException) {
	AudioSourceBase* source_ptr = &source;
	CFArrayRef sources = CFArrayCreate(NULL, (const void**)&source_ptr, 1, &g_weakAudioSourceBaseArrayCallbacks);
	std::vector<Float32>values = std::vector<Float32>(1, value);
	std::vector<Float64>durations = std::vector<Float64>(1, duration);
	RampMixerParameter(sources, kStereoMixerParam_Volume, values, durations);
	CFRelease(sources);
}

void AudioRenderer::RampSourcePan(AudioSourceBase& source, Float32 value, Float64 duration) throw(CAXException) {
	AudioSourceBase* source_ptr = &source;
	CFArrayRef sources = CFArrayCreate(NULL, (const void**)&source_ptr, 1, &g_weakAudioSourceBaseArrayCallbacks);
	std::vector<Float32>values = std::vector<Float32>(1, value);
	std::vector<Float64>durations = std::vector<Float64>(1, duration);
	RampMixerParameter(sources, kStereoMixerParam_Pan, values, durations);
	CFRelease(sources);
}

void AudioRenderer::RampSourcesGain(CFArrayRef sources, Float32 value, Float64 duration) throw(CAXException) {
	std::vector<Float32>values = std::vector<Float32>(CFArrayGetCount(sources), value);
	std::vector<Float64>durations = std::vector<Float64>(CFArrayGetCount(sources), duration);
	RampMixerParameter(sources, kStereoMixerParam_Volume, values, durations);
}

void AudioRenderer::RampSourcesPan(CFArrayRef sources, Float32 value, Float64 duration) throw(CAXException) {
	std::vector<Float32>values = std::vector<Float32>(CFArrayGetCount(sources), value);
	std::vector<Float64>durations = std::vector<Float64>(CFArrayGetCount(sources), duration);
	RampMixerParameter(sources, kStereoMixerParam_Pan, values, durations);
}

void AudioRenderer::RampSourcesGain(CFArrayRef sources, std::vector<Float32>values, std::vector<Float64>durations) throw(CAXException) {
	RampMixerParameter(sources, kStereoMixerParam_Volume, values, durations);
}

void AudioRenderer::RampSourcesPan(CFArrayRef sources, std::vector<Float32>values, std::vector<Float64>durations) throw(CAXException) {
	RampMixerParameter(sources, kStereoMixerParam_Pan, values, durations);
}

#pragma mark -

void AudioRenderer::RampMixerParameter(CFArrayRef sources, AudioUnitParameterID parameter, std::vector<Float32>& values, std::vector<Float64>& durations) throw(CAXException) {
	XThrowIf(CFArrayGetCount(sources) != (CFIndex)values.size(), paramErr, "AudioRenderer::RampMixerParameter (CFArrayGetCount(sources) != (CFIndex)values.size())");
	XThrowIf(CFArrayGetCount(sources) != (CFIndex)durations.size(), paramErr, "AudioRenderer::RampMixerParameter (CFArrayGetCount(sources) != (CFIndex)durations.size())");
	
#if defined(RIVENX)
	bool actuallyScheduleRamps = true;
	if (RXEngineGetBool(@"rendering.audioRamps") == NO) actuallyScheduleRamps = false;
#endif
	
	UInt32 count = CFArrayGetCount(sources);
	UInt32 sourceIndex = 0;
	
	for (; sourceIndex < count; sourceIndex++) {
		AudioSourceBase* source = const_cast<AudioSourceBase *>(reinterpret_cast<const AudioSourceBase*>(CFArrayGetValueAtIndex(sources, sourceIndex)));
		Float32 value = values[sourceIndex];
		Float64 duration = durations[sourceIndex];
		
		XThrowIf(source->rendererPtr != this, paramErr, "AudioRenderer::RampMixerParameter (source->rendererPtr != this)");
		XThrowIf(duration < 0.0, paramErr, "AudioRenderer::RampMixerParameter (duration < 0.0)");
		
#if defined(RIVENX)
		if (actuallyScheduleRamps) {
#endif
			// preapre a new ramp descriptor
			ParameterRampDescriptor descriptor;
			descriptor.source = source;
			descriptor.batch = _currentRampBatch;
			
			// an invalid start timestamp indicates it's a new ramp
			descriptor.start.mFlags = 0;
			descriptor.previous.mFlags = 0;
			
			// setup the parameter event structure
			descriptor.event.scope = kAudioUnitScope_Input;
			descriptor.event.element = source->bus;
			descriptor.event.parameter = parameter;
			descriptor.event.eventType = kParameterEvent_Ramped;
			
			// we need to use the mixer output element's sampling rate to compute the duration (since the pre-render callback is on that unit)
			Float64 sr;
			mixer->GetSampleRate(kAudioUnitScope_Output, 0, sr);
			
			// set up the ramp parameters
			descriptor.event.eventValues.ramp.durationInFrames = static_cast<UInt32>(ceil(sr * duration));
			descriptor.event.eventValues.ramp.startBufferOffset = 0;
			descriptor.event.eventValues.ramp.endValue = value;
			
			// remove and add. I know, doesn't sound logical. Read the source code for TThreadSafeList.
			rampDescriptorList.deferred_remove(descriptor);
			rampDescriptorList.deferred_add(descriptor);
#if defined(RIVENX)
		} else SetSourceGain(*source, value);
#endif
	}
	
	// bump the batch counter
	_currentRampBatch++;
}

OSStatus AudioRenderer::MixerPreRenderNotify(const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, AudioBufferList* ioData) throw() {
	// first, update the list of ramp descriptors
	rampDescriptorList.update();
	
	// we can now iterate over it safely
	TThreadSafeList<ParameterRampDescriptor>::iterator begin = rampDescriptorList.begin();
	TThreadSafeList<ParameterRampDescriptor>::iterator end = rampDescriptorList.end();
	
	while (begin != end) {
		OSStatus err = noErr;
		ParameterRampDescriptor descriptor = *begin;
		begin++;
		
		// if the associated source is no longer attached, remove the descriptor
		if (descriptor.source->rendererPtr != this) {
			rampDescriptorList.deferred_remove(descriptor);
			continue;
		}
		
		if (!(descriptor.start.mFlags & kAudioTimeStampSampleTimeValid)) {
			// if the source is disabled, just slip over the descriptor and leave it as-is
			if (!descriptor.source->enabled)
				continue;
			
			// this is a new ramp parameter descriptor
			descriptor.start = *inTimeStamp;
			descriptor.previous = *inTimeStamp;
			err = mixer->GetParameter(descriptor.event.parameter, kAudioUnitScope_Input, descriptor.event.element, descriptor.event.eventValues.ramp.startValue);
			if (err != noErr) {
				fprintf(stderr, "mixer->GetParameter for %ld, %d, %ld failed with error %ld\n", descriptor.event.parameter, kAudioUnitScope_Input, descriptor.event.element, err);
				return err;
			}
			
#if defined(DEBUG) && DEBUG > 1
			fprintf(stderr, "%f - new ramp: {element=%lu, start=%f, end=%f, duration=%lu}\n", 
				CFAbsoluteTimeGetCurrent(),
				descriptor.event.element,
				descriptor.event.eventValues.ramp.startValue,
				descriptor.event.eventValues.ramp.endValue,
				descriptor.event.eventValues.ramp.durationInFrames);
#endif
			
			// the desciptor is ready, schedule it
			if (!_coarseRamps) {
				err = AudioUnitScheduleParameters(*mixer, &(descriptor.event), 1);
				if (err != noErr) {
					fprintf(stderr, "AudioUnitScheduleParameters failed with error %ld\n", err);
					return err;
				}
			}
			
			rampDescriptorList.deferred_remove(descriptor);
			rampDescriptorList.deferred_add(descriptor);
		} else {
			if (!descriptor.source->enabled) {
				// if the source is disabled, bump the start time so that the ramp will resume when the source is enabled
				descriptor.start.mSampleTime += inTimeStamp->mSampleTime - descriptor.previous.mSampleTime;
				
				 // update the previous timestamp
				descriptor.previous = *inTimeStamp;
				
				rampDescriptorList.deferred_remove(descriptor);
				rampDescriptorList.deferred_add(descriptor);
				
				continue;
			}
			
			// update the start buffer offset
			descriptor.event.eventValues.ramp.startBufferOffset = static_cast<SInt32>(round(descriptor.start.mSampleTime - inTimeStamp->mSampleTime));
			if (static_cast<SInt32>(descriptor.event.eventValues.ramp.durationInFrames) > abs(descriptor.event.eventValues.ramp.startBufferOffset)) {
				// this is an ongoing ramp
#if defined(DEBUG) && DEBUG > 2
				  fprintf(stderr, "	   %f - ongoing ramp: {start=%f, end=%f, bufferOffset=%ld}\n", 
					CFAbsoluteTimeGetCurrent(),
					descriptor.event.eventValues.ramp.startValue, 
					descriptor.event.eventValues.ramp.endValue, 
					descriptor.event.eventValues.ramp.startBufferOffset);
#endif
				
				// schedule the ramp
				if (!_coarseRamps) {
					err = AudioUnitScheduleParameters(*mixer, &(descriptor.event), 1);
					if (err != noErr) {
						fprintf(stderr, "AudioUnitScheduleParameters failed with error %ld\n", err);
						return err;
					}
				} else {
					float t = static_cast<float>(abs(descriptor.event.eventValues.ramp.startBufferOffset)) / descriptor.event.eventValues.ramp.durationInFrames;
					float v = (t * descriptor.event.eventValues.ramp.endValue) + ((1.0f - t) * descriptor.event.eventValues.ramp.startValue);
					if (isnan(v) || !isnormal(v))
						v = 0.0f;
					else if (isinf(v))
						v = 1.0f;
					err = mixer->SetParameter(descriptor.event.parameter, descriptor.event.scope, descriptor.event.element, v);
					if (err != noErr) {
						fprintf(stderr, "mixer->SetParameter failed with error %ld\n", err);
						return err;
					}
				}
				
				// update the previous timestamp
				descriptor.previous = *inTimeStamp;
				
				rampDescriptorList.deferred_remove(descriptor);
				rampDescriptorList.deferred_add(descriptor);
			} else {
				// this ramp is over
#if defined(DEBUG) && DEBUG > 1
				fprintf(stderr, "%f - completed ramp: {element=%lu, start=%f, end=%f, bufferOffset=%ld}\n", 
					CFAbsoluteTimeGetCurrent(),
					descriptor.event.element,
					descriptor.event.eventValues.ramp.startValue,
					descriptor.event.eventValues.ramp.endValue,
					descriptor.event.eventValues.ramp.startBufferOffset);
#endif
				
				if (_coarseRamps) {
					err = mixer->SetParameter(descriptor.event.parameter, descriptor.event.scope, descriptor.event.element, descriptor.event.eventValues.ramp.endValue);
					if (err != noErr) {
						fprintf(stderr, "mixer->SetParameter failed with error %ld\n", err);
						return err;
					}
				}
				
				rampDescriptorList.deferred_remove(descriptor);
			}
		}
	}
	
	return noErr;
}

OSStatus AudioRenderer::MixerPostRenderNotify(const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, AudioBufferList* ioData) throw() {
	// last, update the list of ramp descriptors (again)
	rampDescriptorList.update();
	return noErr;
}

void AudioRenderer::CreateGraph() {
	// main processing graph
	XThrowIfError(NewAUGraph(&graph), "NewAUGraph");
	
	// add the default output AU to the graph
	CAComponentDescription cd;
	cd.componentType = kAudioUnitType_Output;
	cd.componentSubType = kAudioUnitSubType_DefaultOutput;
	cd.componentManufacturer = kAudioUnitManufacturer_Apple;
	
	AUNode outputNode;
	XThrowIfError(AUGraphNewNode(graph, &cd, 0, NULL, &outputNode), "AUGraphNewNode");
	
	// add in the stereo mixer
	cd.componentType = kAudioUnitType_Mixer;
	cd.componentSubType = kAudioUnitSubType_StereoMixer;
	cd.componentManufacturer = kAudioUnitManufacturer_Apple;
	
	AUNode mixerNode;
	XThrowIfError(AUGraphNewNode(graph, &cd, 0, NULL, &mixerNode), "AUGraphNewNode");
	
	// open the graph so that the mixer and AUHAL units are instanciated
	XThrowIfError(AUGraphOpen(graph), "AUGraphOpen");
	
	// get the mixer AU
	AudioUnit mixerAU;
	XThrowIfError(AUGraphGetNodeInfo(graph, mixerNode, NULL, NULL, NULL, &mixerAU), "AUGraphGetNodeInfo");
	
	// make the CAAudioUnit for the mixer
	mixer = new CAAudioUnit(mixerNode, mixerAU);
	
	// set a silence render callback on mixer bus 0 to allow starting without any sources
	AURenderCallbackStruct renderCallback = {RXAudioRendererSilenceRenderCallback, NULL};
	XThrowIfError(mixer->SetProperty(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderCallback, sizeof(renderCallback)), "CAAudioUnit::SetProperty");
	
	// add a pre-render callback on the mixer so we can schedule gain and pan ramps
	XThrowIfError(mixer->AddRenderNotify(AudioRenderer::MixerRenderNotifyCallback, this), "CAAudioUnit::AddRenderNotify");
	
	// FIXME: set channel configuration and such
	
	// connect the output unit and the mixer
	XThrowIfError(AUGraphConnectNodeInput(graph, *mixer, 0, outputNode, 0), "AUGraphConnectNodeInput");
	
	// cache the maximum number of inputs the mixer accepts
	UInt32 limitSize = sizeof(UInt32);
	XThrowIfError(AudioUnitGetProperty(*mixer, kAudioUnitProperty_BusCount, kAudioUnitScope_Input, 0, &sourceLimit, &limitSize), "AudioUnitGetProperty");
	sourceCount = 0;
	
	// create the bus node and allocation vectors
	busNodeVector = new std::vector<AUNode>(sourceLimit);
	busAllocationVector = new std::vector<bool>(sourceLimit);
}

void AudioRenderer::TeardownGraph() {
	// uninitialize, close, dispose
	XThrowIfError(AUGraphUninitialize(graph), "AUGraphUninitialize");
	XThrowIfError(AUGraphClose(graph), "AUGraphClose");
	XThrowIfError(DisposeAUGraph(graph), "DisposeAUGraph");
	
	// none of these are valid anymore
	delete mixer; mixer = 0;
	graph = 0;
	
	delete busNodeVector; busNodeVector = 0;
	delete busAllocationVector; busAllocationVector = 0;
}

}
