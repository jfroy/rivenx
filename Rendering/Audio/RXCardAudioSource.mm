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
	
	// keep our decompressor around
	[_decompressor retain];
	
	// we don't have to reset the decompressor here -- we can do it in HandleAttach
	
	// set our format to the decompressor's format
	format = CAStreamBasicDescription([_decompressor outputFormat]);
	
	// CardAudioSource only handles interleaved formats
	assert(format.IsInterleaved());
	
	// 2 seconds per tasking round
	size_t framesPerTask = static_cast<size_t>(2.0 * format.mSampleRate);
	_bytesPerTask = framesPerTask * format.mBytesPerFrame;
	
	// 10 second buffer
	_decompressionBuffer = [[VirtualRingBuffer alloc] initWithLength:_bytesPerTask * 10];
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
	if (!_decompressor || !_decompressionBuffer)
		return;
	pthread_mutex_lock(&_taskMutex);
	if (!_decompressor || !_decompressionBuffer)
		return;

	task(_bytesPerTask);
	
	pthread_mutex_unlock(&_taskMutex);
}

void CardAudioSource::task(uint32_t byte_limit) throw() {
#if defined(DEBUG) && DEBUG > 2
		CFStringRef rxar_debug = CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::CardAudioSource: 0x%x> tasking"), this);
		RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, rxar_debug);
		CFRelease(rxar_debug);
#endif
	
	// get how many bytes are available in the decompression ring buffer and a suitable write pointer
	void* write_ptr = NULL;
	UInt32 available_bytes = [_decompressionBuffer lengthAvailableToWriteReturningPointer:&write_ptr];
	
	// we want to fill as many bytes as are available in the decompression buffer up to the specified byte limit
	UInt32 bytes_to_fill = (available_bytes < byte_limit) ? available_bytes : byte_limit;
	if (bytes_to_fill == 0) {
#if defined(DEBUG) && DEBUG > 2
		CFStringRef rxar_debug = CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::CardAudioSource: 0x%x> no space for tasking, bailing"), this);
		RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, rxar_debug);
		CFRelease(rxar_debug);
#endif
		return;
	}
		
	// assert that we cannot have more buffered frames than the total number of frames in our decompressor
	assert(_bufferedFrames <= [_decompressor frameCount]);
	
	// derive how many frames we ideally want to fill from the number of bytes to fill
	uint32_t frames_to_fill = format.BytesToFrames(bytes_to_fill);
	if (frames_to_fill == 0) {
#if defined(DEBUG) && DEBUG > 2
		CFStringRef rxar_debug = CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::CardAudioSource: 0x%x> no space for tasking at least one frame, bailing"), this);
		RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, rxar_debug);
		CFRelease(rxar_debug);
#endif
		return;
	}
	
	// derive how many frames can be written in the decompression buffer; if we can fill in more than what we ideally want, clamp to the ideal number
	uint32_t available_frames = (uint32_t)([_decompressor frameCount] - _bufferedFrames);
	if (available_frames > frames_to_fill)
		available_frames = frames_to_fill;
	
	// we fill as many bytes as the number of available frames (clamped to the ideal number of frames)
	bytes_to_fill = format.FramesToBytes(available_frames);
	
	// prepare a suitable ABL
	AudioBufferList abl;
	abl.mNumberBuffers = 1;
	abl.mBuffers[0].mNumberChannels = format.mChannelsPerFrame;
	abl.mBuffers[0].mDataByteSize = bytes_to_fill;
	abl.mBuffers[0].mData = write_ptr;
	
	// fill in the ABL
	[_decompressor fillAudioBufferList:&abl];
	
	// buffer accounting
	_bufferedFrames += available_frames;
	frames_to_fill -= available_frames;
	
	// update the ring buffer
	[_decompressionBuffer didWriteLength:bytes_to_fill];
	
	// if we're looping and we're missing frames from the ideal number, reset the decompressor and go for another round
	if (_loop && frames_to_fill > 0) {
		[_decompressor reset];
		_bufferedFrames = 0;
		
		task(format.FramesToBytes(frames_to_fill));
	}
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
	
	// go for 1 round of tasking so we don't starve the first few callbacks
	RenderTask();
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
