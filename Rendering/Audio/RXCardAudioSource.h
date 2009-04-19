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

#include <libkern/OSAtomic.h>
#include <MHKKit/MHKAudioDecompression.h>

#include "RXAudioSourceBase.h"

#include "RXAtomic.h"
#include "VirtualRingBuffer.h"

namespace RX {

class CardAudioSource : public AudioSourceBase {
public:
	static OSStatus RXCardAudioSourceRenderCallback(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData);

	CardAudioSource(id <MHKAudioDecompression> decompressor, float gain, float pan, bool loop) throw(CAXException);
	virtual ~CardAudioSource() throw(CAXException);
	
	// rendering
	void RenderTask() throw();
	void Reset() throw();
	
	// info 
	inline int64_t FrameCount() const throw() {return [_decompressor frameCount];}
	inline double Duration() const throw() {return [_decompressor frameCount] / format.mSampleRate;}
	
	// nominal gain
	inline float NominalGain() const throw() {return _gain;}
	inline void SetNominalGain(float g) throw() {_gain = g;}
	
	// nominal pan
	inline float NominalPan() const throw() {return _pan;}
	inline void SetNominalPan(float p) throw() {_pan = p;}
	
	// looping
	inline bool Looping() const throw() {return _loop;}
	inline void SetLooping(bool loop) throw() {_loop = loop;}
	
protected:
	virtual void HandleAttach() throw(CAXException);
	virtual void HandleDetach() throw(CAXException);
	
	virtual bool Enable() throw(CAXException);
	virtual bool Disable() throw(CAXException);
	
	virtual OSStatus Render(AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inNumberFrames, AudioBufferList* ioData) throw();

private:
	void task(uint32_t byte_limit) throw();

	id <MHKAudioDecompression> _decompressor;
	float _gain;
	float _pan;
	bool _loop;
	
	VirtualRingBuffer* _decompressionBuffer;
	VirtualRingBuffer* volatile _render_buffer;
	OSSpinLock _buffer_swap_lock;
	
	int64_t _bufferedFrames;
	uint32_t _bytesPerTask;
	
	uint8_t* _loopBuffer;
	uint8_t* _loopBufferEnd;
	uint8_t* _loopBufferReadPointer;
	uint64_t _loopBufferLength;
	
	OSSpinLock _task_lock;
};


}

#endif // _RXCardAudioSource_
