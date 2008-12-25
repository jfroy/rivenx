/*	Copyright © 2007 Apple Inc. All Rights Reserved.
	
	Disclaimer: IMPORTANT:  This Apple software is supplied to you by 
			Apple Inc. ("Apple") in consideration of your agreement to the
			following terms, and your use, installation, modification or
			redistribution of this Apple software constitutes acceptance of these
			terms.  If you do not agree with these terms, please do not use,
			install, modify or redistribute this Apple software.
			
			In consideration of your agreement to abide by the following terms, and
			subject to these terms, Apple grants you a personal, non-exclusive
			license, under Apple's copyrights in this original Apple software (the
			"Apple Software"), to use, reproduce, modify and redistribute the Apple
			Software, with or without modifications, in source and/or binary forms;
			provided that if you redistribute the Apple Software in its entirety and
			without modifications, you must retain this notice and the following
			text and disclaimers in all such redistributions of the Apple Software. 
			Neither the name, trademarks, service marks or logos of Apple Inc. 
			may be used to endorse or promote products derived from the Apple
			Software without specific prior written permission from Apple.  Except
			as expressly stated in this notice, no other rights or licenses, express
			or implied, are granted by Apple herein, including but not limited to
			any patent rights that may be infringed by your derivative works or by
			other works in which the Apple Software may be incorporated.
			
			The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
			MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
			THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
			FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
			OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
			
			IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
			OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
			SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
			INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
			MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
			AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
			STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
			POSSIBILITY OF SUCH DAMAGE.
*/
#ifndef __CAAudioFile_h__
#define __CAAudioFile_h__

#include <AvailabilityMacros.h>

#if !defined(__COREAUDIO_USE_FLAT_INCLUDES__)
	#include <AudioToolbox/AudioToolbox.h>
#else
	#include <AudioToolbox.h>
#endif

#include "CAStreamBasicDescription.h"
#include "CABufferList.h"
#include "CAAudioChannelLayout.h"
#include "CAXException.h"
#include "CAMath.h"

#if !defined(__COREAUDIO_USE_FLAT_INCLUDES__)
	#include <AudioToolbox/ExtendedAudioFile.h>
#else
	#include "ExtendedAudioFile.h"
#endif

// _______________________________________________________________________________________
// Wrapper class for an AudioFile, supporting encode/decode to/from a PCM client format
class CAAudioFile {
public:
	// implementation-independent helpers
	void	Open(const char *filePath) {
		FSRef fsref;
		XThrowIfError(FSPathMakeRef((UInt8 *)filePath, &fsref, NULL), "locate audio file");
		Open(fsref);
	}

	bool							HasConverter() const { return GetConverter() != NULL; }

	double  GetDurationSeconds() {
		double sr = GetFileDataFormat().mSampleRate;
		return fnonzero(sr) ? GetNumberFrames() / sr : 0.;
	}
				// will be 0 if the file's frames/packet is 0 (variable)
				// or the file's sample rate is 0 (unknown)

public:
	CAAudioFile() : mExtAF(NULL), mWrappedFileIDToDispose(NULL) { }
	virtual ~CAAudioFile() 
	{ 
		if (mExtAF) Close(); 
		if (mWrappedFileIDToDispose) AudioFileClose(mWrappedFileIDToDispose); 
	}

	void	Open(const FSRef &fsref, UInt32 inTrackNum) {
			// open an existing file
		if (inTrackNum == 0)
			Open(fsref);
		else {
			AudioFileID afid;
			XThrowIfError(AudioFileOpen(&fsref, fsRdPerm, 0, &afid), "AudioFileOpen failed");

			UInt32 trackCount;
			UInt32 propertySize = sizeof(trackCount);
			XThrowIfError(AudioFileGetProperty(afid, 'atct' /*kAudioFilePropertyAudioTrackCount*/, &propertySize, &trackCount), "Track Count");
			
			if (inTrackNum >= trackCount)
				XThrowIfError (paramErr, "Track count");
			
			XThrowIfError (AudioFileSetProperty (afid, 'uatk' /*kAudioFilePropertyUseAudioTrack*/, sizeof(inTrackNum), &inTrackNum), "Set Track");
			Wrap (afid, false);
			mWrappedFileIDToDispose = afid;
		}
	}

	void	Open(const FSRef &fsref) {
				// open an existing file
		XThrowIfError(ExtAudioFileOpen(&fsref, &mExtAF), "ExtAudioFileOpen failed");
	}
	
	void	CreateNew(const FSRef &inParentDir, CFStringRef inFileName,	AudioFileTypeID inFileType, const AudioStreamBasicDescription &inStreamDesc, const AudioChannelLayout *inChannelLayout=NULL) {
		XThrowIfError(ExtAudioFileCreateNew(&inParentDir, inFileName, inFileType, &inStreamDesc, inChannelLayout, &mExtAF), "ExtAudioFileCreateNew failed");
	}

	void	Wrap(AudioFileID fileID, bool forWriting) {
				// use this to wrap an AudioFileID opened externally
		XThrowIfError(ExtAudioFileWrapAudioFileID(fileID, forWriting, &mExtAF), "ExtAudioFileWrapAudioFileID failed");
	}
	
	void	Close() {
		XThrowIfError(ExtAudioFileDispose(mExtAF), "ExtAudioFileClose failed");
		mExtAF = NULL;
	}

	const CAStreamBasicDescription &GetFileDataFormat() {
		UInt32 size = sizeof(mFileDataFormat);
		XThrowIfError(ExtAudioFileGetProperty(mExtAF, kExtAudioFileProperty_FileDataFormat, &size, &mFileDataFormat), "Couldn't get file's data format");
		return mFileDataFormat;
	}
	
	const CAAudioChannelLayout &	GetFileChannelLayout() {
		return FetchChannelLayout(mFileChannelLayout, kExtAudioFileProperty_FileChannelLayout);
	}
	
	void	SetFileChannelLayout(const CAAudioChannelLayout &layout) {
		XThrowIfError(ExtAudioFileSetProperty(mExtAF, kExtAudioFileProperty_FileChannelLayout, layout.Size(), &layout.Layout()), "Couldn't set file's channel layout");
		mFileChannelLayout = layout;
	}

	const CAStreamBasicDescription &GetClientDataFormat() {
		UInt32 size = sizeof(mClientDataFormat);
		XThrowIfError(ExtAudioFileGetProperty(mExtAF, kExtAudioFileProperty_ClientDataFormat, &size, &mClientDataFormat), "Couldn't get client data format");
		return mClientDataFormat;
	}
	
	const CAAudioChannelLayout &	GetClientChannelLayout() {
		return FetchChannelLayout(mClientChannelLayout, kExtAudioFileProperty_ClientChannelLayout);
	}
	
	void	SetClientFormat(const CAStreamBasicDescription &dataFormat, const CAAudioChannelLayout *layout=NULL) {
		XThrowIfError(ExtAudioFileSetProperty(mExtAF, kExtAudioFileProperty_ClientDataFormat, sizeof(dataFormat), &dataFormat), "Couldn't set client format");
		if (layout)
			SetClientChannelLayout(*layout);
	}
	
	void	SetClientChannelLayout(const CAAudioChannelLayout &layout) {
		XThrowIfError(ExtAudioFileSetProperty(mExtAF, kExtAudioFileProperty_ClientChannelLayout, layout.Size(), &layout.Layout()), "Couldn't set client channel layout");
	}
	
	AudioConverterRef				GetConverter() const {
		UInt32 size = sizeof(AudioConverterRef);
		AudioConverterRef converter;
		XThrowIfError(ExtAudioFileGetProperty(mExtAF, kExtAudioFileProperty_AudioConverter, &size, &converter), "Couldn't get file's AudioConverter");
		return converter;
	}

	OSStatus	SetConverterProperty(AudioConverterPropertyID inPropertyID,	UInt32 inPropertyDataSize, const void *inPropertyData, bool inCanFail=false)
	{
		OSStatus err = AudioConverterSetProperty(GetConverter(), inPropertyID, inPropertyDataSize, inPropertyData);
		if (!inCanFail)
			XThrowIfError(err, "Couldn't set audio converter property");
		if (!err) {
			// must tell the file that we have changed the converter; a NULL converter config is sufficient
			CFPropertyListRef config = NULL;
			XThrowIfError(ExtAudioFileSetProperty(mExtAF, kExtAudioFileProperty_ConverterConfig, sizeof(CFPropertyListRef), &config), "couldn't signal the file that the converter has changed");
		}
		return err;
	}
	
	SInt64		GetNumberFrames() {
		SInt64 length;
		UInt32 size = sizeof(SInt64);
		XThrowIfError(ExtAudioFileGetProperty(mExtAF, kExtAudioFileProperty_FileLengthFrames, &size, &length), "Couldn't get file's length");
		return length;
	}
	
	void		SetNumberFrames(SInt64 length) {
		XThrowIfError(ExtAudioFileSetProperty(mExtAF, kExtAudioFileProperty_FileLengthFrames, sizeof(SInt64), &length), "Couldn't set file's length");
	}
	
	void		Seek(SInt64 pos) {
		XThrowIfError(ExtAudioFileSeek(mExtAF, pos), "Couldn't seek in audio file");
	}
	
	SInt64		Tell() {
		SInt64 pos;
		XThrowIfError(ExtAudioFileTell(mExtAF, &pos), "Couldn't get file's mark");
		return pos;
	}
	
	void		Read(UInt32 &ioFrames, AudioBufferList *ioData) {
		XThrowIfError(ExtAudioFileRead(mExtAF, &ioFrames, ioData), "Couldn't read audio file");
	}

	void		Write(UInt32 inFrames, const AudioBufferList *inData) {
		XThrowIfError(ExtAudioFileWrite(mExtAF, inFrames, inData), "Couldn't write audio file");
	}

	void		SetIOBufferSizeBytes(UInt32 bufferSizeBytes) {
		XThrowIfError(ExtAudioFileSetProperty(mExtAF, kExtAudioFileProperty_IOBufferSizeBytes, sizeof(UInt32), &bufferSizeBytes), "Couldn't set audio file's I/O buffer size");
	}
	
	void		EnableInstrumentation(bool en) {
		UInt32 val = en;
		ExtAudioFileSetProperty(mExtAF, '$ins', sizeof(UInt32), &val);
	}
	
	CFDictionaryRef	GetInstrumentationData() {
		CFDictionaryRef result = NULL;
		UInt32 size = sizeof(result);
		/*OSStatus err =*/ ExtAudioFileGetProperty(mExtAF, '$ind', &size, &result);
		return result;
	}

private:
	const CAAudioChannelLayout &	FetchChannelLayout(CAAudioChannelLayout &layoutObj, ExtAudioFilePropertyID propID) {
		UInt32 size;
		XThrowIfError(ExtAudioFileGetPropertyInfo(mExtAF, propID, &size, NULL), "Couldn't get info about channel layout");
		AudioChannelLayout *layout = (AudioChannelLayout *)malloc(size);
		OSStatus err = ExtAudioFileGetProperty(mExtAF, propID, &size, layout);
		if (err) {
			free(layout);
			XThrowIfError(err, "Couldn't get channel layout");
		}
		layoutObj = layout;
		free(layout);
		return layoutObj;
	}


private:
	ExtAudioFileRef				mExtAF;

	CAStreamBasicDescription	mFileDataFormat;
	CAAudioChannelLayout		mFileChannelLayout;

	CAStreamBasicDescription	mClientDataFormat;
	CAAudioChannelLayout		mClientChannelLayout;

	AudioFileID					mWrappedFileIDToDispose;
};

#endif // __CAAudioFile_h__
