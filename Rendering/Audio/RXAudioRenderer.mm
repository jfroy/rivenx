//
//  RXAudioRenderer.cpp
//  rivenx
//
//  Created by Jean-Francois Roy on 15/02/2006.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import <algorithm>

#import <libkern/OSAtomic.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreServices/CoreServices.h>

#import "Base/RXAtomic.h"
#import "Base/RXLogging.h"

#import "RXAudioRenderer.h"
#import "RXAudioSourceBase.h"

#if defined(RIVENX)
#import "Engine/RXWorldProtocol.h"
#endif

#import "Rendering/Audio/PublicUtility/CAComponentDescription.h"
#import "Rendering/Audio/PublicUtility/CAAUParameter.h"
#import "Rendering/Audio/PublicUtility/CAStreamBasicDescription.h"

namespace RX {

static OSStatus RXAudioRendererSilenceRenderCallback(void                           *inRefCon, 
                                                     AudioUnitRenderActionFlags     *ioActionFlags, 
                                                     const AudioTimeStamp           *inTimeStamp, 
                                                     UInt32                         inBusNumber, 
                                                     UInt32                         inNumberFrames, 
                                                     AudioBufferList                *ioData)
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

OSStatus AudioRenderer::MixerRenderNotifyCallback(void                           *inRefCon, 
                                                  AudioUnitRenderActionFlags     *ioActionFlags, 
                                                  const AudioTimeStamp           *inTimeStamp, 
                                                  UInt32                         inBusNumber, 
                                                  UInt32                         inNumberFrames, 
                                                  AudioBufferList                *ioData)
{
    RX::AudioRenderer* renderer = reinterpret_cast<RX::AudioRenderer*>(inRefCon);
    if (*ioActionFlags & kAudioUnitRenderAction_PreRender)
        return renderer->MixerPreRenderNotify(inTimeStamp, inNumberFrames, ioData);
    if (*ioActionFlags & kAudioUnitRenderAction_PostRender)
        return renderer->MixerPostRenderNotify(inTimeStamp, inNumberFrames, ioData);
    return noErr;
}

#pragma mark -

AudioRenderer::AudioRenderer() throw(CAXException) :
graph(0),
output(0),
mixer(0),
_automaticGraphUpdates(true),
_graphUpdateNeeded(false),
sourceLimit(0),
sourceCount(0),
busNodeVector(0),
busAllocationVector(0)
{
    CreateGraph();
    RXCFLog(kRXLoggingAudio, kRXLoggingLevelMessage, CFSTR("<RX::AudioRenderer: 0x%x> initialized with %u mixer inputs"), this, sourceLimit);
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
            if (err != kAUGraphErr_CannotDoInCurrentContext && err != noErr)
                XThrowIfError(err, "AUGraphUpdate");
        }
    }
    
    // update _automaticGraphUpdates
    _automaticGraphUpdates = b;
    
    // if automatic updates are enabled, set _graphUpdateNeeded to false
    if (_automaticGraphUpdates)
        _graphUpdateNeeded = false;
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
    
    // source index also turns out to be the number of sources we attached successfully
    for (; sourceIndex < count; sourceIndex++) {
        source = const_cast<AudioSourceBase *>(reinterpret_cast<const AudioSourceBase*>(CFArrayGetValueAtIndex(sources, sourceIndex)));
        XThrowIf(source == NULL, paramErr, "AudioRenderer::AttachSources (source == NULL)");
        
        // if the source is already attached to this renderer, move on
        if (source->rendererPtr == this) {
            RXCFLog(kRXLoggingAudio, kRXLoggingLevelMessage, CFSTR("AudioRenderer::AttachSources: skipping source %p because it is already attached"), source);
            continue;
        }
        
        // if the source is already attached to a different renderer, bail for this source
        XThrowIf(source->rendererPtr != 0 && source->rendererPtr != this, paramErr, "AudioRenderer::AttachSources (source->rendererPtr != 0 && source->rendererPtr != this)");
        
        // if the mixer cannot accept more connections, bail
        if (sourceCount >= sourceLimit) {
            RXCFLog(kRXLoggingAudio, kRXLoggingLevelMessage, CFSTR("AudioRenderer::AttachSources: mixer has no available input busses left, dropping %d sources"), count - (sourceIndex + 1));
            break;
        }
        
        // find the next available bus, bail if there are no more busses
        std::vector<bool>::iterator busIterator;
        busIterator = find(busAllocationVector->begin(), busAllocationVector->end(), false);
        if (busIterator == busAllocationVector->end() && busAllocationVector->size() == sourceLimit) {
            RXCFLog(kRXLoggingAudio, kRXLoggingLevelMessage, CFSTR("AudioRenderer::AttachSources: mixer has no available input busses left, dropping %d sources"), count - (sourceIndex + 1));
            break;
        }
        
        // if the source format is invalid or not mixable, bail for this source
        if (!CAStreamBasicDescription::IsMixable(source->Format())) {
            RXCFLog(kRXLoggingAudio, kRXLoggingLevelMessage, CFSTR("AudioRenderer::AttachSources: skipping source %p because its format is not mixable"), source);
            continue;
        }
        
        // compute and set the source's bus index
        source->bus = static_cast<AudioUnitElement>(busIterator - busAllocationVector->begin());
        
        // a non-NULL renderer means the source has been attached properly
        source->rendererPtr = this;
        
        // set nominal gain and pan parameters
        SetSourceGain(*source, 1.0f);
        SetSourcePan(*source, 0.5f);
        
        // let the source know it's being attached
        source->HandleAttach();
        
        // try to set the format of the source as the mixer's input bus format; this will more often than not fail
        CAStreamBasicDescription source_format = source->Format();
        OSStatus oserr = (source_format.NumberChannels() == 1) ? kAudioUnitErr_FormatNotSupported : mixer->SetFormat(kAudioUnitScope_Input, source->bus, source->Format());
        if (oserr == kAudioUnitErr_FormatNotSupported) {
            // we need to create a converter AU and connect it to the mixer, plugging the source as the converter's render callback
            
#if defined(DEBUG_AUDIO) && DEBUG_AUDIO > 1
            RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, CFSTR("<RX::AudioRenderer: 0x%x> creating ancillary converter for source %p on bus %u"), this, source, source->bus);
#endif
            
            // create a new graph node with the converter AU
            AudioComponentDescription acd;
            acd.componentType = kAudioUnitType_FormatConverter;
            acd.componentSubType = kAudioUnitSubType_AUConverter;
            acd.componentManufacturer = kAudioUnitManufacturer_Apple;
            acd.componentFlags = 0;
            acd.componentFlagsMask = 0;
            
            // convert to a CAAudioUnit object
            AUNode converter_node;
            AudioUnit converter_au;
            XThrowIfError(AUGraphAddNode(graph, &acd, &converter_node), "AUGraphAddNode kAudioUnitSubType_AUConverter");
            XThrowIfError(AUGraphNodeInfo(graph, converter_node, NULL, &converter_au), "AUGraphNodeInfo");
            //XThrowIfError(AUGraphNewNode(graph, &acd, 0, NULL, &converter_node), "AUGraphNewNode kAudioUnitSubType_AUConverter");
            //XThrowIfError(AUGraphGetNodeInfo(graph, converter_node, NULL, NULL, NULL, &converter_au), "AUGraphGetNodeInfo");
            CAAudioUnit converter = CAAudioUnit(converter_node, converter_au);
            
            // set the input and output formats of the converter
            XThrowIfError(converter.SetFormat(kAudioUnitScope_Input, 0, source_format), "converter->SetFormat kAudioUnitScope_Input");
            CAStreamBasicDescription mixer_format;
            XThrowIfError(mixer->GetFormat(kAudioUnitScope_Input, source->bus, mixer_format), "mixer->GetFormat kAudioUnitScope_Input");
            XThrowIfError(converter.SetFormat(kAudioUnitScope_Output, 0, mixer_format), "converter->SetFormat kAudioUnitScope_Output");
            
            // set the channel map of the converter if the source format is mono (we need to replicate the mono channel)
            debug_assert(mixer_format.NumberChannels() == 2);
            if (source_format.NumberChannels() == 1) {
                SInt32 channel_map[2] = {0, 0};
                XThrowIfError(converter.SetProperty(kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Global, 0, channel_map, sizeof(SInt32) * 2), "converter.SetProperty kAudioOutputUnitProperty_ChannelMap");
            }
            
            // set the render callback on the converter
            AURenderCallbackStruct render_callbacks = {AudioSourceBase::AudioSourceRenderCallback, source};
            XThrowIfError(converter.SetProperty(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &render_callbacks, sizeof(AURenderCallbackStruct)), "converter->SetProperty kAudioUnitProperty_SetRenderCallback");
            
            // and finally plug the converter in
            XThrowIfError(AUGraphConnectNodeInput(graph, converter_node, 0, *mixer, source->bus), "AUGraphConnectNodeInput");
            (*busNodeVector)[source->bus] = converter_node;
        } else {
            XThrowIfError(oserr, "mixer->SetFormat");
            
            // set the source's render function as the mixer's render callback
            AURenderCallbackStruct render_callbacks = {AudioSourceBase::AudioSourceRenderCallback, source};
            XThrowIfError(mixer->SetProperty(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, source->bus, &render_callbacks, sizeof(AURenderCallbackStruct)), "mixer->SetProperty kAudioUnitProperty_SetRenderCallback");
            
            // make sure the node for this bus is 0
            (*busNodeVector)[source->bus] = static_cast<AUNode>(0);
        }
        
        // account for the new connection
        sourceCount++;
        (*busAllocationVector)[source->bus] = true;
        
#if defined(DEBUG_AUDIO) && DEBUG_AUDIO > 1
        RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, CFSTR("<RX::AudioRenderer: 0x%x> attached source %p to bus %u"), this, source, source->bus);
#endif
    }
    
    // if the graph is running or initialized, we need to schedule a graph update
    if (_must_update_graph_predicate())
        XThrowIfError(AUGraphUpdate(graph, NULL), "AUGraphUpdate");
    
    return sourceIndex;
}

void AudioRenderer::DetachSources(CFArrayRef sources) throw (CAXException) {
    XThrowIf(sources == 0, paramErr, "AudioRenderer::DetachSources");
    UInt32 count = CFArrayGetCount(sources);
    UInt32 sourceIndex = 0;
    
    AudioUnitElement* busToRecycle = new AudioUnitElement[count];
    XThrowIf(busToRecycle == 0, mFulErr, "AudioRenderer::DetachSources");
    
    for (; sourceIndex < count; sourceIndex++) {
        AudioSourceBase* source = const_cast<AudioSourceBase*>(reinterpret_cast<const AudioSourceBase*>(CFArrayGetValueAtIndex(sources, sourceIndex)));
        XThrowIf(source->rendererPtr != this, paramErr, "AudioRenderer::DetachSources: tried to detach a source not attached to the renderer");
        
#if defined(DEBUG_AUDIO) && DEBUG_AUDIO > 1
        RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, CFSTR("<RX::AudioRenderer: 0x%x> detaching source %p from bus %u"), this, source, source->bus);
#endif
        
        // if this source has no node, then it was connected directly to the mixer and we so we need to reset the mixer's render callback to the silence callback
        if ((*busNodeVector)[source->bus]) {
            // we have to disconnect the converter node at this time
            XThrowIfError(AUGraphDisconnectNodeInput(graph, *mixer, source->bus), "AUGraphDisconnectNodeInput");
        }
        
        // set the silence render callback on the mixer bus
        AURenderCallbackStruct silence_render = {RXAudioRendererSilenceRenderCallback, 0};
        XThrowIfError(mixer->SetProperty(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, source->bus, &silence_render, sizeof(AURenderCallbackStruct)), "mixer->SetProperty kAudioUnitProperty_SetRenderCallback");
        
        // invalidate any ongoing ramps for this source; a parameter of UINTMAX is a special value which will match all parameters
        ParameterRampDescriptor descriptor;
        descriptor.generation = pending_ramp_generation++;
        descriptor.event.element = source->bus;
        descriptor.event.parameter = UINT32_MAX;
        pending_ramps.deferred_add(descriptor);
        
        // retain the source's bus before we zero it in the source for the code that comes after the required graph update below
        busToRecycle[sourceIndex] = source->bus;
        
        // invalidate the source's bus and renderer
        source->bus = 0;
        source->rendererPtr = 0;
        
        // let the source know it was detached
        source->HandleDetach();
    }
    
    // if the graph is running or initialized, we need to schedule a graph update before we can remove the nodes
    if (_must_update_graph_predicate())
        XThrowIfError(AUGraphUpdate(graph, NULL), "AUGraphUpdate");
    
    for (sourceIndex = 0; sourceIndex < count; sourceIndex++) {
        // if the source had a converter node, we can now remove it from the graph
        if ((*busNodeVector)[busToRecycle[sourceIndex]]) {
            XThrowIfError(AUGraphRemoveNode(graph, (*busNodeVector)[busToRecycle[sourceIndex]]), "AUGraphRemoveNode");
            (*busNodeVector)[busToRecycle[sourceIndex]] = static_cast<AUNode>(0);
        }
        
        // account for the lost connection
        sourceCount--;
        (*busAllocationVector)[busToRecycle[sourceIndex]] = false;
    }
    
    delete[] busToRecycle;
}

Float32 AudioRenderer::SourceGain(AudioSourceBase& source) const throw(CAXException) {
    Float32 value;
    XThrowIfError(mixer->GetParameter(kStereoMixerParam_Volume, kAudioUnitScope_Input, source.bus, value), "mixer->GetParameter kStereoMixerParam_Volume");
    return powf(value, 3.0f);
}

Float32 AudioRenderer::SourcePan(AudioSourceBase& source) const throw(CAXException) {
    // get the raw value
    Float32 value;
    XThrowIfError(mixer->GetParameter(kStereoMixerParam_Pan, kAudioUnitScope_Input, source.bus, value), "mixer->GetParameter kStereoMixerParam_Pan");
    return value;
}

void AudioRenderer::SetSourceGain(AudioSourceBase& source, Float32 gain) throw(CAXException) {
    RampSourceGain(source, gain, 0.0);
}

void AudioRenderer::SetSourcePan(AudioSourceBase& source, Float32 pan) throw(CAXException) {
    RampSourcePan(source, pan, 0.0);
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

void AudioRenderer::RampMixerParameter(CFArrayRef sources, AudioUnitParameterID parameter_id, std::vector<Float32>& values, std::vector<Float64>& durations) throw(CAXException) {
    XThrowIf(CFArrayGetCount(sources) != (CFIndex)values.size(), paramErr, "AudioRenderer::RampMixerParameter (CFArrayGetCount(sources) != (CFIndex)values.size())");
    XThrowIf(CFArrayGetCount(sources) != (CFIndex)durations.size(), paramErr, "AudioRenderer::RampMixerParameter (CFArrayGetCount(sources) != (CFIndex)durations.size())");
    
    bool ramps_are_enabled = true;
#if defined(RIVENX)
    if (RXEngineGetBool(@"rendering.audio_ramps") == NO)
        ramps_are_enabled = false;
#endif
    
    UInt32 count = CFArrayGetCount(sources);
    UInt32 sourceIndex = 0;
    
    for (; sourceIndex < count; sourceIndex++) {
        AudioSourceBase* source = const_cast<AudioSourceBase *>(reinterpret_cast<const AudioSourceBase*>(CFArrayGetValueAtIndex(sources, sourceIndex)));
        Float32 value = values[sourceIndex];
        Float64 duration = durations[sourceIndex];
        
        XThrowIf(source->rendererPtr != this, paramErr, "AudioRenderer::RampMixerParameter (source->rendererPtr != this)");
        XThrowIf(duration < 0.0, paramErr, "AudioRenderer::RampMixerParameter (duration < 0.0)");
        
        // get the parameter information structure
        CAAUParameter parameter = CAAUParameter(*mixer, parameter_id, kAudioUnitScope_Input, source->bus);
        AudioUnitParameterInfo parameter_info = parameter.ParamInfo();
        
        // clamp the value to the valid range for the parameter
        value = MAX(MIN(value, parameter_info.maxValue), parameter_info.minValue);
        
        // prepare a new ramp descriptor
        ParameterRampDescriptor descriptor;
        descriptor.generation = pending_ramp_generation++;
        descriptor.source = source;
        
        // an invalid start timestamp indicates it's a new ramp
        descriptor.start.mFlags = 0;
        descriptor.previous.mFlags = 0;
        
        // setup the parameter event structure
        descriptor.event.scope = kAudioUnitScope_Input;
        descriptor.event.element = source->bus;
        descriptor.event.parameter = parameter_id;
        descriptor.event.eventType = (fabs(duration) < 1.0e-3 || !ramps_are_enabled) ? kParameterEvent_Immediate : kParameterEvent_Ramped;
        
        // we need to take the cube root of the value if the parameter is volume
        if (parameter_id == kStereoMixerParam_Volume)
            value = cbrt(value);
        
        if (descriptor.event.eventType == kParameterEvent_Ramped) {
            // we need to use the mixer output element's sampling rate to compute the duration (since the pre-render callback is on that unit)
            Float64 sr;
            mixer->GetSampleRate(kAudioUnitScope_Output, 0, sr);
            
            // set up the ramp parameters
            descriptor.event.eventValues.ramp.durationInFrames = static_cast<UInt32>(ceil(sr * duration));
            descriptor.event.eventValues.ramp.startBufferOffset = 0;
            descriptor.event.eventValues.ramp.endValue = value;
        } else {
            // set up the immediate parameters
            descriptor.event.eventValues.immediate.bufferOffset = 0;
            descriptor.event.eventValues.immediate.value = value;
        }
        
        // we first remove any existing ramp descriptor before adding the new descriptor in
        pending_ramps.deferred_add(descriptor);
    }
}

OSStatus AudioRenderer::MixerPreRenderNotify(const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, AudioBufferList* ioData) throw() {
    OSStatus err = noErr;
    
    // first, update the list of pending ramp descriptors
    pending_ramps.update();
    
    // now iterate over the pending descriptors and remove/add into the list of active descriptors
    TThreadSafeList<ParameterRampDescriptor>::iterator pending;
    for (pending = pending_ramps.begin(); pending != pending_ramps.end(); ++pending) {
        ParameterRampDescriptor descriptor = *pending;
        pending_ramps.deferred_remove(descriptor);
        
        // set the descriptor's generation to 0 (there cannot be more than one descriptor for each element-parameter pair)
        descriptor.generation = 0;
        
        // if the descriptor has the parameter set to UINT32_MAX, it basically means to remove all ramps for the descriptor's element
        if (descriptor.event.parameter == UINT32_MAX) {
            TThreadSafeList<ParameterRampDescriptor>::iterator active;
            for (active = active_ramps.begin(); active != active_ramps.end(); ++active) {
                if ((*active).event.element == descriptor.event.element)
                    active_ramps.deferred_remove(*active);
            }
            
#if defined(DEBUG_AUDIO) && DEBUG_AUDIO > 1
            RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, CFSTR("%f - removed all ramps for element %lu"), CFAbsoluteTimeGetCurrent(), descriptor.event.element);
#endif
        } else {
            // if the descriptor indicates an immediate change, apply it now and move on to the next descriptor
            if (descriptor.event.eventType == kParameterEvent_Immediate) {
                err = mixer->SetParameter(descriptor.event.parameter, descriptor.event.scope, descriptor.event.element, descriptor.event.eventValues.immediate.value);
                if (err != noErr) {
#if defined(DEBUG_AUDIO)
                    RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, CFSTR("mixer->SetParameter failed with error %ld"), err);
#endif
                    return err;
                }
            } else {
                // otherwise remove-add the descriptor from-to the active list
                active_ramps.deferred_remove(descriptor);
                active_ramps.deferred_add(descriptor);
            }
        }
    }
    
    // update the active ramps list
    active_ramps.update();
    
    // finally iterate over the active ramps
    TThreadSafeList<ParameterRampDescriptor>::iterator active;
    for (active = active_ramps.begin(); active != active_ramps.end(); ++active) {
        ParameterRampDescriptor& descriptor_ref = *active;
        
        // if the associated source is no longer attached to us, remove the descriptor and move on to the next
        if (descriptor_ref.source->rendererPtr != this) {
            active_ramps.deferred_remove(descriptor_ref);
            continue;
        }
        
        if (!(descriptor_ref.start.mFlags & kAudioTimeStampSampleTimeValid)) {
            // if the source is disabled, just slip over the descriptor and leave it as-is
            if (!descriptor_ref.source->enabled)
                continue;
            
            // this is a new ramp parameter descriptor
            
            // set the start and previous timestamps to the pre-render notification timestamp (e.g. now)
            descriptor_ref.start = *inTimeStamp;
            descriptor_ref.previous = *inTimeStamp;
            
            // get the start value for the ramp's parameter
            err = mixer->GetParameter(descriptor_ref.event.parameter, kAudioUnitScope_Input, descriptor_ref.event.element, descriptor_ref.event.eventValues.ramp.startValue);
            if (err != noErr) {
#if defined(DEBUG_AUDIO)
                RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, CFSTR("mixer->GetParameter for %ld, %d, %ld failed with error %ld"), descriptor_ref.event.parameter, kAudioUnitScope_Input, descriptor_ref.event.element, err);
#endif
                return err;
            }
            
#if defined(DEBUG_AUDIO) && DEBUG_AUDIO > 1
            RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, CFSTR("%f - new ramp: {element=%lu, parameter=%lu, start=%f, end=%f, duration=%lu}"), 
                CFAbsoluteTimeGetCurrent(),
                descriptor_ref.event.element,
                descriptor_ref.event.parameter,
                descriptor_ref.event.eventValues.ramp.startValue,
                descriptor_ref.event.eventValues.ramp.endValue,
                descriptor_ref.event.eventValues.ramp.durationInFrames);
#endif
        } else {
            if (!descriptor_ref.source->enabled) {
                // if the source is disabled, bump the start time so that the ramp will resume when the source is enabled
                descriptor_ref.start.mSampleTime += inTimeStamp->mSampleTime - descriptor_ref.previous.mSampleTime;
                
                 // update the previous timestamp
                descriptor_ref.previous = *inTimeStamp;
                
                // move on to the next ramp
                continue;
            }
            
            // update the start buffer offset
            descriptor_ref.event.eventValues.ramp.startBufferOffset = static_cast<SInt32>(round(descriptor_ref.start.mSampleTime - inTimeStamp->mSampleTime));
            if (static_cast<SInt32>(descriptor_ref.event.eventValues.ramp.durationInFrames) > abs(descriptor_ref.event.eventValues.ramp.startBufferOffset)) {
                // this is an ongoing ramp
#if defined(DEBUG_AUDIO) && DEBUG_AUDIO > 2
                  RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, CFSTR("       %f - ongoing ramp: {element=%lu, parameter=%lu, start=%f, end=%f, bufferOffset=%ld}"), 
                    CFAbsoluteTimeGetCurrent(),
                    descriptor_ref.event.element,
                    descriptor_ref.event.parameter,
                    descriptor_ref.event.eventValues.ramp.startValue, 
                    descriptor_ref.event.eventValues.ramp.endValue, 
                    descriptor_ref.event.eventValues.ramp.startBufferOffset);
#endif
                
                // apply the ramp (use use linear parameter value interpolation with time being the sole interpolation parameter)
                float t = static_cast<float>(abs(descriptor_ref.event.eventValues.ramp.startBufferOffset)) / descriptor_ref.event.eventValues.ramp.durationInFrames;
                float v = (t * descriptor_ref.event.eventValues.ramp.endValue) + ((1.0f - t) * descriptor_ref.event.eventValues.ramp.startValue);
                if (isnan(v) || !isnormal(v))
                    v = 0.0f;
                else if (isinf(v))
                    v = 1.0f;
                err = mixer->SetParameter(descriptor_ref.event.parameter, descriptor_ref.event.scope, descriptor_ref.event.element, v);
                if (err != noErr) {
#if defined(DEBUG_AUDIO)
                    RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, CFSTR("mixer->SetParameter failed with error %ld"), err);
#endif
                    return err;
                }
                
                // update the previous timestamp
                descriptor_ref.previous = *inTimeStamp;
            } else {
                // this ramp is over
#if defined(DEBUG_AUDIO) && DEBUG_AUDIO > 1
                RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, CFSTR("%f - completed ramp: {element=%lu, parameter=%lu, start=%f, end=%f, bufferOffset=%ld}"), 
                    CFAbsoluteTimeGetCurrent(),
                    descriptor_ref.event.element,
                    descriptor_ref.event.parameter,
                    descriptor_ref.event.eventValues.ramp.startValue,
                    descriptor_ref.event.eventValues.ramp.endValue,
                    descriptor_ref.event.eventValues.ramp.startBufferOffset);
#endif

                // apply the final ramp parameter value (without interpolation)
                err = mixer->SetParameter(descriptor_ref.event.parameter, descriptor_ref.event.scope, descriptor_ref.event.element, descriptor_ref.event.eventValues.ramp.endValue);

                // remove the ramp from the active list
                active_ramps.deferred_remove(descriptor_ref);
            }
        }
    }
    
    return noErr;
}

OSStatus AudioRenderer::MixerPostRenderNotify(const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, AudioBufferList* ioData) throw() {
    return noErr;
}

void AudioRenderer::CreateGraph() {
    AudioComponentDescription acd;
    acd.componentType = 0;
    acd.componentSubType = 0;
    acd.componentManufacturer = kAudioUnitManufacturer_Apple;
    acd.componentFlags = 0;
    acd.componentFlagsMask = 0;
    AudioUnit au;

    // main processing graph
    XThrowIfError(NewAUGraph(&graph), "NewAUGraph");
    
    // add the default output AU to the graph
    AUNode output_node;
    acd.componentType = kAudioUnitType_Output;
    acd.componentSubType = kAudioUnitSubType_DefaultOutput;
    XThrowIfError(AUGraphAddNode(graph, &acd, &output_node), "AUGraphAddNode kAudioUnitSubType_DefaultOutput");
    //XThrowIfError(AUGraphNewNode(graph, &acd, 0, NULL, &output_node), "AUGraphNewNode");
    
    // add in the stereo mixer
    AUNode mixer_node;
    acd.componentType = kAudioUnitType_Mixer;
    acd.componentSubType = kAudioUnitSubType_StereoMixer;
    XThrowIfError(AUGraphAddNode(graph, &acd, &mixer_node), "AUGraphAddNode kAudioUnitSubType_StereoMixer");
    //XThrowIfError(AUGraphNewNode(graph, &acd, 0, NULL, &mixer_node), "AUGraphNewNode");
    
    // open the graph so that the mixer and AUHAL units are instanciated
    XThrowIfError(AUGraphOpen(graph), "AUGraphOpen");
    
    // get the output unit
    XThrowIfError(AUGraphNodeInfo(graph, output_node, NULL, &au), "AUGraphNodeInfo");
    //XThrowIfError(AUGraphGetNodeInfo(graph, output_node, NULL, NULL, NULL, &au), "AUGraphGetNodeInfo");
    output = new CAAudioUnit(output_node, au);
    
    // get the mixer unit
    XThrowIfError(AUGraphNodeInfo(graph, mixer_node, NULL, &au), "AUGraphNodeInfo");
    //XThrowIfError(AUGraphGetNodeInfo(graph, mixer_node, NULL, NULL, NULL, &au), "AUGraphGetNodeInfo");
    mixer = new CAAudioUnit(mixer_node, au);
    
    // configure the format and channel layout of the output and mixer units
    
    // get the output format of the output unit (e.g. the hardware output format)
    CAStreamBasicDescription format;
    XThrowIfError(output->GetFormat(kAudioUnitScope_Output, 0, format), "output->GetFormat");
    
    // make the format canonical, with 2 non-interleaved channels (Riven X is a stereo application) at a sampling rate of 44100 Hz
    format.SetCanonical(2, false);
    format.mSampleRate = 44100;
    
    // set the format as the output unit's input format and th mixer unit's output format
    XThrowIfError(output->SetFormat(kAudioUnitScope_Input, 0, format), "output->SetFormat");
    XThrowIfError(mixer->SetFormat(kAudioUnitScope_Output, 0, format), "mixer->SetFormat");
    
    // add a pre-render callback on the mixer so we can schedule gain and pan ramps
    XThrowIfError(mixer->AddRenderNotify(AudioRenderer::MixerRenderNotifyCallback, this), "CAAudioUnit::AddRenderNotify");
    
    // connect the output unit and the mixer
    XThrowIfError(AUGraphConnectNodeInput(graph, *mixer, 0, output_node, 0), "AUGraphConnectNodeInput");
    
    // set the maximum number of mixer inputs to 16
    sourceLimit = 16;
    XThrowIfError(mixer->SetProperty(kAudioUnitProperty_BusCount, kAudioUnitScope_Input, 0, &sourceLimit, sizeof(UInt32)), "mixer->SetProperty kAudioUnitProperty_BusCount");
    sourceCount = 0;
    
    // set a silence render callback on the mixer input busses
    AURenderCallbackStruct silence_render = {RXAudioRendererSilenceRenderCallback, 0};
    for (AudioUnitElement element = 0; element < 16; element++)
        XThrowIfError(mixer->SetProperty(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, element, &silence_render, sizeof(AURenderCallbackStruct)), "mixer->SetProperty kAudioUnitProperty_SetRenderCallback");
    
    // create the bus node and allocation vectors
    busNodeVector = new std::vector<AUNode>(sourceLimit);
    busAllocationVector = new std::vector<bool>(sourceLimit);
}

void AudioRenderer::TeardownGraph() {
    // uninitialize, close, dispose
    XThrowIfError(AUGraphUninitialize(graph), "AUGraphUninitialize");
    XThrowIfError(AUGraphClose(graph), "AUGraphClose");
    XThrowIfError(DisposeAUGraph(graph), "DisposeAUGraph");
    
    // clean up
    delete output; output = 0;
    delete mixer; mixer = 0;
    graph = 0;
    
    delete busNodeVector; busNodeVector = 0;
    delete busAllocationVector; busAllocationVector = 0;
}

}
