/*
 *	RXCardAudioSource.mm
 *	rivenx
 *
 *	Created by Jean-Francois Roy on 08/03/2006.
 *	Copyright 2006 MacStorm. All rights reserved.
 *
 */

#include "RXCardAudioSource.h"

namespace RX {

CardAudioSource::CardAudioSource(id <MHKAudioDecompression> decompressor, float gain, float pan, bool loop) throw(CAXException) : _decompressor(decompressor), _gain(gain), _pan(pan), _loop(loop)
{
	pthread_mutex_init(&_taskMutex, NULL);
	
	[_decompressor retain];
	[_decompressor reset];
	
	format = CAStreamBasicDescription([_decompressor outputFormat]);
	assert(format.IsInterleaved());
	
	// cache some values from the decompressor
	_frames = [_decompressor frameCount];
	
	// 5 seconds buffer
	size_t framesPerTask = static_cast<size_t>(5.0 * format.mSampleRate);
	_bytesPerTask = framesPerTask * format.mBytesPerFrame;
	
	_decompressionBuffer = [[VirtualRingBuffer alloc] initWithLength:_bytesPerTask];
	_bufferedFrames = 0;
	
	_loopBuffer = 0;
}

CardAudioSource::~CardAudioSource() throw(CAXException) {
	pthread_mutex_lock(&_taskMutex);
	
	Finalize();
	
	[_decompressor release];
	[_decompressionBuffer release];
	
	if (_loopBuffer)
		free(_loopBuffer);
	
	pthread_mutex_destroy(&_taskMutex);
}

OSStatus CardAudioSource::Render(AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inNumberFrames, AudioBufferList* ioData) throw() {	
	// if there is no decompressor or decompression buffer, or we are disabled, render silence
	if (!Enabled() || !rendererPtr || !_decompressor || !_decompressionBuffer) {
		for (UInt32 bufferIndex = 0; bufferIndex < ioData->mNumberBuffers; bufferIndex++)
			bzero(ioData->mBuffers[bufferIndex].mData, ioData->mBuffers[bufferIndex].mDataByteSize);
		*ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
		
#if defined(DEBUG) && DEBUG > 2
		CFStringRef rxar_debug = CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::CardAudioSource: 0x%x> rendering silence because disabled, no renderer, no decompressor or no decompression buffer"), this);
		RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, rxar_debug);
		CFRelease(rxar_debug);
#endif
		return noErr;
	}
	
	// buffer housekeeping
	UInt32 optimalBytesToRead = inNumberFrames * format.mBytesPerFrame;
	assert(ioData->mBuffers[0].mDataByteSize == optimalBytesToRead);
	
	void* readBuffer = 0;
	UInt32 availableBytes = (_decompressionBuffer) ? [_decompressionBuffer lengthAvailableToReadReturningPointer:&readBuffer] : 0U;
	
	// if there are no samples available, render silence
	if (availableBytes == 0) {
		for (UInt32 bufferIndex = 0; bufferIndex < ioData->mNumberBuffers; bufferIndex++)
			bzero(ioData->mBuffers[bufferIndex].mData, ioData->mBuffers[bufferIndex].mDataByteSize);
		*ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
		
#if defined(DEBUG) && DEBUG > 1
		CFStringRef rxar_debug = CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::CardAudioSource: 0x%x> rendering silence because of sample starvation"), this);
		RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, rxar_debug);
		CFRelease(rxar_debug);
#endif
		return noErr;
	}
	
	// handle either the normal or the overload case
	if (availableBytes >= optimalBytesToRead) {
		memcpy(ioData->mBuffers[0].mData, readBuffer, optimalBytesToRead);
		[_decompressionBuffer didReadLength:optimalBytesToRead];
	} else {
#if defined(DEBUG) && DEBUG > 1
		CFStringRef rxar_debug = CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::CardAudioSource: 0x%x> rendering silence because of partial sample starvation"), this);
		RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, rxar_debug);
		CFRelease(rxar_debug);
#endif
		memcpy(ioData->mBuffers[0].mData, readBuffer, availableBytes);
		[_decompressionBuffer didReadLength:availableBytes];
		bzero(reinterpret_cast<unsigned char*>(ioData->mBuffers[0].mData) + availableBytes, optimalBytesToRead - availableBytes);
	}
	
	return noErr;
}

void CardAudioSource::RenderTask() throw() {
	if (!rendererPtr || !_decompressor || !_decompressionBuffer)
		return;
	pthread_mutex_lock(&_taskMutex);
	if (!rendererPtr || !_decompressor || !_decompressionBuffer)
		return;
	
	void* write_ptr = NULL;
	UInt32 available_bytes = [_decompressionBuffer lengthAvailableToWriteReturningPointer:&write_ptr];
	UInt32 bytes_to_fill = (available_bytes < _bytesPerTask) ? available_bytes : _bytesPerTask;
	if (bytes_to_fill == 0) {
		pthread_mutex_unlock(&_taskMutex);
		return;
	}
		
	// buffer housekeeping
	assert(_frames >= _bufferedFrames);
	
	uint32_t available_frames = (uint32_t)(_frames - _bufferedFrames);
	uint32_t frames_to_fill = format.BytesToFrames(bytes_to_fill);
	if (available_frames > frames_to_fill)
		available_frames = frames_to_fill;
	
	while (frames_to_fill > 0) {
		uint32_t bytes_to_fill = format.FramesToBytes(available_frames);
		
		// prepare a suitable ABL
		AudioBufferList abl;
		abl.mNumberBuffers = 1;
		abl.mBuffers[0].mNumberChannels = format.mChannelsPerFrame;
		abl.mBuffers[0].mDataByteSize = bytes_to_fill;
		abl.mBuffers[0].mData = write_ptr;
		
		// fill in the ABL
		[_decompressor fillAudioBufferList:&abl];
		
		// buffer accounting
		[_decompressionBuffer didWriteLength:bytes_to_fill];
		_bufferedFrames += available_frames;
		frames_to_fill -= available_frames;
		write_ptr = BUFFER_OFFSET(write_ptr, bytes_to_fill);
		
		// do we need to reset the decompressor?
		if (_loop && frames_to_fill > 0) {
			[_decompressor reset];
			_bufferedFrames = 0;
			
			available_frames = (uint32_t)_frames;
			if (available_frames > frames_to_fill)
				available_frames = frames_to_fill;
		} else
			break;
	}
	
	pthread_mutex_unlock(&_taskMutex);
}

#pragma mark -

void CardAudioSource::HandleAttach() throw(CAXException) {
	// reset the decompressor
	[_decompressor reset];
	
	// reset the decompression state
	[_decompressionBuffer empty];
	_bufferedFrames = 0;
	
	// set the gain and pan
	rendererPtr->SetSourceGain(*this, _gain);
	rendererPtr->SetSourcePan(*this, _pan);
}

void CardAudioSource::HandleDetach() throw(CAXException) {

}

bool CardAudioSource::Enable() throw(CAXException) {
	return true;
}

bool CardAudioSource::Disable() throw(CAXException) {
	return true;
}

} // namespace RX
