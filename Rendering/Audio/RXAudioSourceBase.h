/*
 *	RXAudioSourceBase.h
 *	rivenx
 *
 *	Created by Jean-Francois Roy on 16/02/2006.
 *	Copyright 2006 MacStorm. All rights reserved.
 *
 */

#if !defined(RX_AUDIO_SOURCE_BASE_H)
#define RX_AUDIO_SOURCE_BASE_H

#include "RXAudioRenderer.h"

#include "CAStreamBasicDescription.h"
#include "CAAudioUnit.h"

namespace RX {

class AudioSourceBase {
friend class AudioRenderer;
	
private:
	// WARNING: sub-classes are responsible for checking this variable and should output silence without updating their rendering state if it is true
	bool enabled;
	pthread_mutex_t transitionMutex;
	bool _didFinalize;

public:
	virtual ~AudioSourceBase() throw (CAXException);
	
	// format
	inline CAStreamBasicDescription Format() const throw() {return format;}
	
	// graph
	inline AUGraph Graph() const throw() {return graph;}
	inline const CAAudioUnit& OutputUnit() const throw() {return outputUnit;}
	
	// enabling
	inline bool Enabled() const throw() {return enabled;}
	void SetEnabled(bool enable) throw(CAXException);
	
protected:
	AudioSourceBase() throw(CAXException);
	
	void Finalize() throw(CAXException);
	
	virtual void PopulateGraph() throw(CAXException) = 0;
	virtual void HandleDetach() throw(CAXException) = 0;
	
	virtual bool Enable() throw(CAXException) = 0;
	virtual bool Disable() throw(CAXException) = 0;
	
	CAStreamBasicDescription format;
	
	AUGraph graph;
	CAAudioUnit outputUnit;
	AudioUnitElement bus;
	
	// WARNING: a NULL renderer is the convention for indicating a source is not attached
	AudioRenderer* rendererPtr;
	
private:
	AudioSourceBase (const AudioSourceBase &c) {}
	AudioSourceBase& operator= (const AudioSourceBase& c) {return *this;}
};

}

#endif // RX_AUDIO_SOURCE_BASE_H
