/*
 *	RXCardAudioSource.h
 *	rivenx
 *
 *	Created by Jean-Francois Roy on 08/03/2006.
 *	Copyright 2006 MacStorm. All rights reserved.
 *
 */

#if !defined(_RXCardAudioSource_)
#define _RXCardAudioSource_

#if !defined(__cplusplus)
#error C++ is required to include RXCardAudioSource.h
#endif

#include <pthread.h>
#include <MHKKit/MHKAudioDecompression.h>

#include "RXAudioSourceBase.h"

#include "RXAtomic.h"
#include "VirtualRingBuffer.h"

namespace RX {

class CardAudioSource : public AudioSourceBase {
public:
	CardAudioSource(id <MHKAudioDecompression> decompressor, float gain, float pan, bool loop) throw(CAXException);
	virtual ~CardAudioSource() throw(CAXException);
	
	// looping
	inline bool Looping() const throw() {return _loop;}
	inline void SetLooping(bool loop) throw() {_loop = loop;}
	
	// rendering
	OSStatus Render(AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inNumberFrames, AudioBufferList* ioData) throw();
	void RenderTask() throw();
	
	// info 
	inline int64_t FrameCount() const throw() {return _frames;}
	inline double Duration() const throw() {return _frames / format.mSampleRate;}
	
	// nominal gain
	inline float NominalGain() const throw() {return _gain;}
	inline void SetNominalGain(float g) throw() {_gain = g;}
	
protected:
	virtual void PopulateGraph() throw(CAXException);
	virtual void HandleDetach() throw(CAXException);
	
	virtual bool Enable() throw(CAXException);
	virtual bool Disable() throw(CAXException);

private:
	id <MHKAudioDecompression> _decompressor;
	float _gain;
	float _pan;
	bool _loop;
	
	int64_t _frames;
	
	int64_t _bufferedFrames;
	VirtualRingBuffer* _decompressionBuffer;
	uint32_t _bytesPerTask;
	
	uint8_t* _loopBuffer;
	uint8_t* _loopBufferEnd;
	uint8_t* _loopBufferReadPointer;
	uint64_t _loopBufferLength;
	
	pthread_mutex_t _taskMutex;
};


}

#endif // _RXCardAudioSource_
