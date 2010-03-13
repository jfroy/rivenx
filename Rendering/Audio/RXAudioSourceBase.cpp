/*
 *  RXAudioSourceBase.cpp
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 16/02/2006.
 *  Copyright 2005-2010 MacStorm. All rights reserved.
 *
 */

#include <assert.h>

#include "RXAtomic.h"
#include "RXAudioSourceBase.h"

namespace RX {

OSStatus AudioSourceBase::AudioSourceRenderCallback(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData) {
    AudioSourceBase* source = reinterpret_cast<AudioSourceBase*>(inRefCon);
    return source->Render(ioActionFlags, inTimeStamp, inNumberFrames, ioData);
}

AudioSourceBase::AudioSourceBase() throw(CAXException) : enabled(true), rendererPtr(0) {
    pthread_mutex_init(&transitionMutex, NULL);
}

AudioSourceBase::~AudioSourceBase() throw (CAXException) {
    assert(!rendererPtr);
    pthread_mutex_destroy(&transitionMutex);
}

void AudioSourceBase::Finalize() throw(CAXException) {
    this->SetEnabled(false);
    if (rendererPtr)
        rendererPtr->DetachSource(*this);
}

void AudioSourceBase::SetEnabled(bool enable) throw(CAXException) {
    if (enable == this->enabled)
        return;
    pthread_mutex_lock(&transitionMutex);
    
    // callback to the sub-class
    bool success = false;
    if (enable)
        success = this->Enable();
    else
        success = this->Disable();
    
    if (success)
        this->enabled = enable;
    pthread_mutex_unlock(&transitionMutex);
}

OSStatus AudioSourceBase::Render(AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inNumberFrames, AudioBufferList* ioData) throw() {
    UInt32 buffer_index = 0;
    for (; buffer_index < ioData->mNumberBuffers; buffer_index++)
        bzero(ioData->mBuffers[buffer_index].mData, ioData->mBuffers[buffer_index].mDataByteSize);
    *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
    return noErr;
}

}
