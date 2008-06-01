/*
 *	RXAudioSourceBase.cpp
 *	rivenx
 *
 *	Created by Jean-Francois Roy on 16/02/2006.
 *	Copyright 2006 MacStorm. All rights reserved.
 *
 */

#include <assert.h>

#include "RXAtomic.h"
#include "RXAudioSourceBase.h"

namespace RX {

AudioSourceBase::AudioSourceBase() throw(CAXException) : enabled(true), _didFinalize(false) {
	enabled = true;
	pthread_mutex_init(&transitionMutex, NULL);

	rendererPtr = reinterpret_cast<AudioRenderer *>(NULL);
	graph = reinterpret_cast<AUGraph>(NULL);
}

AudioSourceBase::~AudioSourceBase() throw (CAXException) {
	assert(_didFinalize);
	pthread_mutex_destroy(&transitionMutex);
}

void AudioSourceBase::Finalize() throw(CAXException) {
	_didFinalize = true;
	this->SetEnabled(false);
	if (rendererPtr) rendererPtr->DetachSource(*this);
}

void AudioSourceBase::SetEnabled(bool enable) throw(CAXException) {
	if (enable == this->enabled) return;
	pthread_mutex_lock(&transitionMutex);
	
	// callback to the sub-class
	bool success = false;
	if (enable) success = this->Enable();
	else success = this->Disable();
	
	if (success) this->enabled = enable;
	pthread_mutex_unlock(&transitionMutex);
}

}
