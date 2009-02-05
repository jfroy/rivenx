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

static OSStatus RXCardAudioSourceRenderCallback(void							*inRefCon, 
												AudioUnitRenderActionFlags		*ioActionFlags, 
												const AudioTimeStamp			*inTimeStamp, 
												UInt32							inBusNumber, 
												UInt32							inNumberFrames, 
												AudioBufferList					*ioData)
{
	RX::CardAudioSource* source = (RX::CardAudioSource*)inRefCon;
	return source->Render(ioActionFlags, inTimeStamp, inNumberFrames, ioData);
}

CardAudioSource::CardAudioSource(id <MHKAudioDecompression> decompressor, float gain, float pan, bool loop) throw(CAXException) : _decompressor(decompressor), _gain(1.0), _pan(pan), _loop(loop)
{
	pthread_mutex_init(&_taskMutex, NULL);
	
	[_decompressor retain];
	[_decompressor reset];
	
	format = CAStreamBasicDescription([_decompressor outputFormat]);
	
	// cache some values from the decompressor
	_frames = [_decompressor frameCount];
	
	// 0.5 seconds buffer
	size_t framesPerTask = static_cast<size_t>(0.5 * format.mSampleRate);
	_bytesPerTask = framesPerTask * format.mBytesPerFrame;
	
	_decompressionBuffer = [[VirtualRingBuffer alloc] initWithLength:_bytesPerTask];
	_bufferedFrames = 0;
	
	// if the source is looping and is very short, we'll use a loop buffer
	if (_frames < framesPerTask && loop) {
		_loopBufferLength = (_frames * (1 + (framesPerTask / _frames))) * format.mBytesPerFrame;
		_loopBuffer = (uint8_t*)malloc(_loopBufferLength);
		_loopBufferEnd = _loopBuffer + _loopBufferLength;
		
		// Explicit cast is OK, ABL structure takes a 32-bit integer
		uint32_t sourceLength = (uint32_t)(_frames * format.mBytesPerFrame);
		
		// prepare a suitable ABL
		AudioBufferList abl;
		
		// FIXME: assumes interleaved samples
		abl.mNumberBuffers = 1;
		abl.mBuffers[0].mNumberChannels = format.mChannelsPerFrame;
		abl.mBuffers[0].mDataByteSize = sourceLength;
		abl.mBuffers[0].mData = _loopBuffer;
		
		// decompress all the frames into the loop buffer
		[_decompressor fillAudioBufferList:&abl];
		
		_loopBufferReadPointer = _loopBuffer + sourceLength;
		while (_loopBufferReadPointer < _loopBufferEnd) {
			memcpy(_loopBufferReadPointer, _loopBuffer, sourceLength);
			_loopBufferReadPointer += sourceLength;
		}
		
		_loopBufferReadPointer = _loopBuffer;
	} else
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
			CFStringRef rxar_debug = CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::CardAudioSource: 0x%x> rendering silence because disabled, no renderer, no decompressor or not decompression buffer"), this);
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
		
#if defined(DEBUG) && DEBUG > 2
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
		memcpy(ioData->mBuffers[0].mData, readBuffer, availableBytes);
		[_decompressionBuffer didReadLength:availableBytes];
		bzero(reinterpret_cast<unsigned char *>(ioData->mBuffers[0].mData) + availableBytes, optimalBytesToRead - availableBytes);
	}
	
	return noErr;
}

void CardAudioSource::RenderTask() throw() {
	if (!rendererPtr || !_decompressor || !_decompressionBuffer)
		return;
	pthread_mutex_lock(&_taskMutex);
	
	/*	This function is tricky. It has to deal with two issues:
		
		1. Looping or not looping
		2. More frames in the source than frames per task, or less.
	*/
	
	void* writeBuffer = NULL;
	UInt32 availableBytes = [_decompressionBuffer lengthAvailableToWriteReturningPointer:&writeBuffer];
	UInt32 bytesThisTask = (availableBytes < _bytesPerTask) ? availableBytes : _bytesPerTask;
	
	if (bytesThisTask == 0) {
		pthread_mutex_unlock(&_taskMutex);
		return;
	}
	
	// loop buffer branch
	if (_loopBuffer) {
		// stage 1
		assert(_loopBufferEnd >= _loopBufferReadPointer);
		UInt32 bytesToCopy = _loopBufferEnd - _loopBufferReadPointer;
		if (bytesToCopy > bytesThisTask)
			bytesToCopy = bytesThisTask;
		
		if (bytesToCopy > 0) {
			memcpy(writeBuffer, _loopBufferReadPointer, bytesToCopy);
			[_decompressionBuffer didWriteLength:bytesToCopy];
			_loopBufferReadPointer += bytesToCopy;
		}
		
		// stage 2
		assert(_loopBufferReadPointer <= _loopBufferEnd);
		if (_loopBufferReadPointer == _loopBufferEnd)
			_loopBufferReadPointer = _loopBuffer;
		
		// stage 3 (we didn't have enough bytes to fill the ring buffer)
		if (bytesToCopy < bytesThisTask) {
			// we can safely ignore the updated availableBytes, bytesThisTask should still be valid
			availableBytes = [_decompressionBuffer lengthAvailableToWriteReturningPointer:&writeBuffer];
			
			// the math (see ctor) should make it so that we will have enough space in the loop buffer here
			bytesToCopy = bytesThisTask - bytesToCopy;
			
			memcpy(writeBuffer, _loopBufferReadPointer, bytesToCopy);
			[_decompressionBuffer didWriteLength:bytesToCopy];
			_loopBufferReadPointer += bytesToCopy;
		}
		
		pthread_mutex_unlock(&_taskMutex);
		return;
	}
	
	// buffer housekeeping
	assert(_frames >= _bufferedFrames);
	UInt32 bytesRemaining = (UInt32)((_frames - _bufferedFrames) * format.mBytesPerFrame);
	
	UInt32 optimalBytesToWrite = (bytesThisTask < bytesRemaining) ? bytesThisTask : bytesRemaining;
	assert(optimalBytesToWrite <= bytesThisTask);
	
	// bail out if there's nothing to be done
	if (optimalBytesToWrite == 0) {
		pthread_mutex_unlock(&_taskMutex);
		return;
	}
	
	// prepare a suitable ABL
	AudioBufferList abl;
	
	// FIXME: assumes interleaved samples
	abl.mNumberBuffers = 1;
	abl.mBuffers[0].mNumberChannels = format.mChannelsPerFrame;
	abl.mBuffers[0].mDataByteSize = optimalBytesToWrite;
	abl.mBuffers[0].mData = writeBuffer;
	
	// and decompress
	[_decompressor fillAudioBufferList:&abl];
	[_decompressionBuffer didWriteLength:optimalBytesToWrite];
	_bufferedFrames += (SInt64)(optimalBytesToWrite / format.mBytesPerFrame);
	
	// do we need to reset the decompressor?
	if (_loop && _bufferedFrames == _frames) {
		[_decompressor reset];
		_bufferedFrames = 0;
		// Explicit cast OK here, ABL structure takes UInt32
		bytesRemaining = (UInt32)(_frames * format.mBytesPerFrame);
		
		// do we need a second round of decompression?
		if (optimalBytesToWrite < bytesThisTask) {
			// we can safely ignore the updated availableBytes, bytesThisTask should still be valid
			availableBytes = [_decompressionBuffer lengthAvailableToWriteReturningPointer:&writeBuffer];
			assert(availableBytes > 0);
			
			optimalBytesToWrite = bytesThisTask - optimalBytesToWrite;
			assert(optimalBytesToWrite <= bytesThisTask);
			
			// FIXME: assumes interleaved samples
			abl.mNumberBuffers = 1;
			abl.mBuffers[0].mNumberChannels = format.mChannelsPerFrame;
			abl.mBuffers[0].mDataByteSize = optimalBytesToWrite;
			abl.mBuffers[0].mData = writeBuffer;
			
			// and decompress
			[_decompressor fillAudioBufferList:&abl];
			[_decompressionBuffer didWriteLength:optimalBytesToWrite];
			_bufferedFrames += (SInt64)(optimalBytesToWrite / format.mBytesPerFrame);
		}
	}
	
	pthread_mutex_unlock(&_taskMutex);
}

#pragma mark -

void CardAudioSource::PopulateGraph() throw(CAXException) {
	// set the output format on the output node
	XThrowIfError(outputUnit.SetFormat(kAudioUnitScope_Input, 0, format), "CAAudioUnit::SetFormat");
	
	// reset the decompressor
	[_decompressor reset];
	
	// reset the decompression state
	[_decompressionBuffer empty];
	_bufferedFrames = 0;
	_loopBufferReadPointer = _loopBuffer;
	
	// set a render callback on the output node
	AURenderCallbackStruct input = {RXCardAudioSourceRenderCallback, this};
	XThrowIfError(outputUnit.SetProperty(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &input, sizeof(input)), "CAAudioUnit::SetProperty");
	
	// set the gain and pan
	rendererPtr->SetSourceGain(*this, 1.0);
	rendererPtr->SetSourcePan(*this, _pan);
	
#if defined(DEBUG) && DEBUG > 1
	CFStringRef rxar_debug = CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::CardAudioSource: 0x%x> populated graph (gain: %f, pan: %f)"), this, 1.0, _pan);
	RXCFLog(kRXLoggingAudio, kRXLoggingLevelDebug, rxar_debug);
	CFRelease(rxar_debug);
#endif
}

void CardAudioSource::HandleDetach() throw(CAXException) {
	// nothing to do
}

bool CardAudioSource::Enable() throw(CAXException) {
	return true;
}

bool CardAudioSource::Disable() throw(CAXException) {
	return true;
}

} // namespace RX
