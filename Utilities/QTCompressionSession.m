//
//  QTCompressionSession.m
//  rivenx
//
//  Created by Jean-François Roy on 20/08/2006.

/*
Copyright (c) 2006 Jean-François Roy
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. The name of the author may not be used to endorse or promote products
   derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import "QTCompressionSession.h"

#import <QTKit/QTKit.h>


@interface QTCompressionSession (QTCompressionSessionPrivate)
- (OSStatus)_createVideoMedia:(ImageDescriptionHandle)imageDesc timeScale:(TimeScale)timescale;
- (OSStatus)_writeEncodedFrame:(OSStatus)err frame:(ICMEncodedFrameRef)frame;
- (OSStatus)_createCompressionSession;
- (void)_finalizeCompressionSession;
@end

@implementation QTCompressionSession

#pragma mark Class methods

+ (Movie)quicktimeMovieFromTempFile:(DataHandler *)outDataHandler error:(NSError **)error {
    OSStatus outErr = -1;
    
    // Generate a name for our movie file
    NSString* tempName = [NSString stringWithCString:tmpnam(nil) encoding:[NSString defaultCStringEncoding]];
    if (nil == tempName) goto nostring;
    
    Handle dataRefH = nil;
    OSType dataRefType;

    // Create a file data reference for our movie
    outErr = QTNewDataReferenceFromFullPathCFString((CFStringRef)tempName, kQTNativeDefaultPathStyle, 0, &dataRefH, &dataRefType);
    if (outErr != noErr) goto nodataref;
    
    // Create a QuickTime movie from our file data reference
    Movie movie = nil;
    CreateMovieStorage(dataRefH, dataRefType, 'TVOD', smCurrentScript, newMovieActive | createMovieFileDeleteCurFile, outDataHandler, &movie);
    outErr = GetMoviesError();
    if (outErr != noErr) goto cantcreatemovstorage;
    
    NSLog(@"[%@] Created temporary movie storage at %@.", self, tempName);
    
    if (error) *error = nil;
    return movie;

// Error handling
cantcreatemovstorage:
    DisposeHandle(dataRefH);

nodataref:
nostring:

    if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:outErr userInfo:nil];
    return nil;
}

+ (ICMCompressionSessionOptionsRef)compressionOptionsFromStandardCompressionDialog {
    ComponentResult err;
    ICMCompressionSessionOptionsRef optionsRef = NULL;
    
    // Open default compression dialog component
    ComponentInstance standardCompressionDialogComponent;
    err = OpenADefaultComponent(StandardCompressionType, StandardCompressionSubType, &standardCompressionDialogComponent);
    if (err || 0 == standardCompressionDialogComponent) goto bail;
    
    // Allow for frame reordering and other features only available through the newer compression session APIs
    long scFlags = scAllowEncodingWithCompressionSession;
    err = SCSetInfo(standardCompressionDialogComponent, scPreferenceFlagsType, &scFlags);
    if (err) goto bail;
    
    // Display the dialog
    err = SCRequestSequenceSettings(standardCompressionDialogComponent);
    if (err) goto bail;
    
    // Get an ICM compression session options object reference out of the dialog
    err = SCCopyCompressionSessionOptions(standardCompressionDialogComponent, &optionsRef);
    if (err) goto bail;
    
bail:
    if (standardCompressionDialogComponent) CloseComponent(standardCompressionDialogComponent);
    return (ICMCompressionSessionOptionsRef)[(id)optionsRef autorelease];
}

#pragma mark Private methods

// Create a video track and media to hold encoded frames.
// This is called the first time we get an encoded frame back from the compression session.
- (OSStatus)_createVideoMedia:(ImageDescriptionHandle)imageDesc timeScale:(TimeScale)timescale {
    OSStatus err = noErr;
    Fixed trackWidth, trackHeight;
    Track outputTrack = NULL;
    
    err = ICMImageDescriptionGetProperty(imageDesc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_ClassicTrackWidth, sizeof(trackWidth), &trackWidth, NULL);
    if(err) {
        fprintf(stderr, "ICMImageDescriptionGetProperty(kICMImageDescriptionPropertyID_DisplayWidth) failed (%ld)\n", err);
        goto bail;
    }
    
    err = ICMImageDescriptionGetProperty(imageDesc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_ClassicTrackHeight, sizeof(trackHeight), &trackHeight, NULL);
    if(err) {
        fprintf(stderr, "ICMImageDescriptionGetProperty(kICMImageDescriptionPropertyID_DisplayHeight) failed (%ld)\n", err);
        goto bail;
    }
    
    outputTrack = NewMovieTrack(outputMovie, trackWidth, trackHeight, 0);
    err = GetMoviesError();
    if(err) {
        fprintf(stderr, "NewMovieTrack() failed (%ld)\n", err);
        goto bail;
    }
    
    outputVideoMedia = NewTrackMedia(outputTrack, VideoMediaType, timescale, 0, 0);
    err = GetMoviesError();
    if(err) {
        fprintf(stderr, "NewTrackMedia() failed (%ld)\n", err);
        goto bail;
    }
    
    err = BeginMediaEdits(outputVideoMedia);
    if(err) {
        fprintf(stderr, "BeginMediaEdits() failed (%ld)\n", err );
        goto bail;
    }
    
    didBeginVideoMediaEdits = YES;
    
bail:
    return err;
}

// This is the tracking callback function for the compression session.
// Write the encoded frame to the movie file.
// Note that this function adds each sample separately; better chunking can be achieved
// by flattening the movie after it is finished, or by grouping samples, writing them in 
// groups to the data reference manually, and using AddSampleTableToMedia.
- (OSStatus)_writeEncodedFrame:(OSStatus)err frame:(ICMEncodedFrameRef)frame {
    // Bail if the session has errored
    if (err) {
        fprintf(stderr, "writeEncodedFrame received an error (%ld)\n", err);
        goto bail;
    }
    
    // If we don't have an output video media, create it
    if (!outputVideoMedia) {
        ImageDescriptionHandle imageDesc = NULL;
        err = ICMEncodedFrameGetImageDescription(frame, &imageDesc);
        if (err) {
            fprintf(stderr, "ICMEncodedFrameGetImageDescription() failed (%ld)\n", err);
            goto bail;
        }
        
        err = [self _createVideoMedia:imageDesc timeScale:ICMEncodedFrameGetTimeScale(frame)];
        if(err) goto bail;
    }
    
    // Encode the frame if it has duration
    if(ICMEncodedFrameGetDecodeDuration(frame) > 0) {
        err = AddMediaSampleFromEncodedFrame(outputVideoMedia, frame, NULL);
        if (err) {
            fprintf(stderr, "AddMediaSampleFromEncodedFrame() failed (%ld)\n", err);
            goto bail;
        }
    }
    
    // Augment frame counter
    frameCount++;
    
bail:
    return err;
}

static OSStatus write_encoded_frame(void* encodedFrameOutputRefCon, ICMCompressionSessionRef session, OSStatus error, ICMEncodedFrameRef frame, void* reserved) {
    QTCompressionSession* qtcs = encodedFrameOutputRefCon;
    return [qtcs _writeEncodedFrame:error frame:frame];
}

- (OSStatus)_createCompressionSession {
    OSStatus err = noErr;
    ICMEncodedFrameOutputRecord encodedFrameOutputRecord = {0};
    ICMCompressionSessionOptionsRef sessionOptions = NULL;
    
    err = ICMCompressionSessionOptionsCreate(NULL, &sessionOptions);
    if (err) {
        fprintf(stderr, "ICMCompressionSessionOptionsCreate() failed (%ld)\n", err);
        goto bail;
    }
    
    // We must set this flag to enable P or B frames.
    err = ICMCompressionSessionOptionsSetAllowTemporalCompression(sessionOptions, true);
    if (err) {
        fprintf(stderr, "ICMCompressionSessionOptionsSetAllowTemporalCompression() failed (%ld)\n", err);
        goto bail;
    }
    
    // We must set this flag to enable B frames.
    err = ICMCompressionSessionOptionsSetAllowFrameReordering(sessionOptions, true);
    if (err) {
        fprintf(stderr, "ICMCompressionSessionOptionsSetAllowFrameReordering() failed (%ld)\n", err);
        goto bail;
    }
    
    // Set the maximum key frame interval, also known as the key frame rate.
    err = ICMCompressionSessionOptionsSetMaxKeyFrameInterval(sessionOptions, 250);
    if (err) {
        fprintf(stderr, "ICMCompressionSessionOptionsSetMaxKeyFrameInterval() failed (%ld)\n", err);
        goto bail;
    }
    
    // This allows the compressor more flexibility (ie, dropping and coalescing frames).
    err = ICMCompressionSessionOptionsSetAllowFrameTimeChanges(sessionOptions, true);
    if( err ) {
        fprintf(stderr, "ICMCompressionSessionOptionsSetAllowFrameTimeChanges() failed (%ld)\n", err);
        goto bail;
    }
    
    // We need durations when we store frames.
    err = ICMCompressionSessionOptionsSetDurationsNeeded(sessionOptions, true);
    if (err) {
        fprintf(stderr, "ICMCompressionSessionOptionsSetDurationsNeeded() failed (%ld)\n", err);
        goto bail;
    }
    
    // Set the average data rate.
    err = ICMCompressionSessionOptionsSetProperty(sessionOptions, 
                                                  kQTPropertyClass_ICMCompressionSessionOptions, 
                                                  kICMCompressionSessionOptionsPropertyID_AverageDataRate, 
                                                  sizeof(averageDataRate), 
                                                  &averageDataRate);
    if (err) {
        fprintf(stderr, "ICMCompressionSessionOptionsSetProperty(AverageDataRate) failed (%ld)\n", err);
        goto bail;
    }
    
    // kICMCompressionSessionOptionsPropertyID_CPUTimeBudget
    // kICMCompressionSessionOptionsPropertyID_AllowAsyncCompletion
    
    // Explicitely turn off multipass compression
    ICMMultiPassStorageRef nullStorage = NULL;
    ICMCompressionSessionOptionsSetProperty(sessionOptions, 
                                            kQTPropertyClass_ICMCompressionSessionOptions, 
                                            kICMCompressionSessionOptionsPropertyID_MultiPassStorage, 
                                            sizeof(ICMMultiPassStorageRef), 
                                            &nullStorage);
    
    encodedFrameOutputRecord.encodedFrameOutputCallback = write_encoded_frame;
    encodedFrameOutputRecord.encodedFrameOutputRefCon = self;
    encodedFrameOutputRecord.frameDataAllocator = NULL;
    
    err = ICMCompressionSessionCreate(NULL, width, height, codecType, timeScale, sessionOptions, NULL, &encodedFrameOutputRecord, &compressionSession);
    if (err) {
        fprintf(stderr, "ICMCompressionSessionCreate() failed (%ld)\n", err);
        goto bail;
    }
    
bail:
    ICMCompressionSessionOptionsRelease(sessionOptions);
    
    return err;
}

- (void)_finalizeCompressionSession {
    if (!sessionFinalized && compressionSession) {
        sessionFinalized = YES;
        
        // It is important to push out any remaining frames before we release the compression session.
        // If we knew the timestamp following the last source frame, you should pass it in here.
        ICMCompressionSessionCompleteFrames(compressionSession, true, 0, 0);
        ICMCompressionSessionRelease(compressionSession);
        compressionSession = NULL;
    }
}

- (void)dealloc {
    if (outputMovieDataHandler) CloseMovieStorage(outputMovieDataHandler);
    if (outputMovie) DisposeMovie(outputMovie);
    if (compressionSession) ICMCompressionSessionRelease(compressionSession);
    
    
    [super dealloc];
}

#pragma mark Public methods

- (id)init {
    // Make sure client goes through designated initializer
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)initToTempMovieWithWidth:(int)w height:(int)h timeScale:(TimeScale)ts error:(NSError **)error {
    self = [super init];
    
    // Parameters
    width = w;
    height = h;
    timeScale = ts;
    
    // This really should be configurable
    codecType = kH264CodecType;
    averageDataRate = 100000; // 100 kbyte/sec == 800 kbit/sec
    desiredFramesPerSecond = 15;
    
    // Create output movie
    outputMovie = [[self class] quicktimeMovieFromTempFile:&outputMovieDataHandler error:error];
    if (!outputMovie) {
        [self release];
        return nil;
    }
    
    // Create our compression session
    OSStatus err = [self _createCompressionSession];
    if (err) {
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
        [self release];
        return nil;
    }
    
    didBeginVideoMediaEdits = NO;
    sessionFinalized = NO;
    
    return self;
}

- (OSStatus)compressFrame:(CVPixelBufferRef)frame timeStamp:(NSTimeInterval)timestamp duration:(NSTimeInterval)duration {
    OSStatus err;
    
    // Do nothing if the compression session has been finalized
    if (sessionFinalized) return noErr;
    
    // Pass frame to compression session
    err = ICMCompressionSessionEncodeFrame(compressionSession, 
                                           frame, 
                                           (timestamp >= 0.0 ? (SInt64)(timestamp * timeScale) : 0), 
                                           (duration >= 0.0 ? (SInt64)(duration * timeScale) : 0), 
                                           ((timestamp >= 0.0 ? kICMValidTime_DisplayTimeStampIsValid : 0) | (duration >= 0.0 ? kICMValidTime_DisplayDurationIsValid : 0)), 
                                           NULL, 
                                           NULL, 
                                           NULL);
    if(err) fprintf(stderr, "ICMCompressionSessionEncodeFrame() failed (%ld)\n", err);
    return err;
}

- (void)finishOutputMovieToPath:(NSString *)path {
    OSStatus err = noErr;
    if (!path) return;
    
    // Implicitly finalize the compression session
    [self _finalizeCompressionSession];
    
    if (didBeginVideoMediaEdits) {
        // End the media sample-adding session.
        err = EndMediaEdits(outputVideoMedia);
        if (err) {
            fprintf(stderr, "EndMediaEdits() failed (%ld)\n", err);
            goto bail;
        }
    
        // Make sure things are extra neat
        ExtendMediaDecodeDurationToDisplayEndTime(outputVideoMedia, NULL);
        
        // Insert the stuff we added into the track, at the end.
        Track videoTrack = GetMediaTrack(outputVideoMedia);
        err = InsertMediaIntoTrack(videoTrack, GetTrackDuration(videoTrack), 0, GetMediaDisplayDuration(outputVideoMedia), fixed1);
        if (err) {
            fprintf(stderr, "InsertMediaIntoTrack() failed (%ld)\n", err);
            goto bail;
        }
    }
    
    // Write the movie header to the file.
    err = AddMovieToStorage(outputMovie, outputMovieDataHandler);
    if (err) {
        fprintf(stderr, "AddMovieToStorage() failed (%ld)\n", err);
        goto bail;
    }
    
    // Get storage path
    CFStringRef tempPath;
    err = QTGetDataHandlerFullPathCFString(outputMovieDataHandler, kQTNativeDefaultPathStyle, &tempPath);
    if (err) {
        fprintf(stderr, "QTGetDataHandlerFullPathCFString() failed (%ld)\n", err);
        goto bail;
    }
    
    // Close the storage
    CloseMovieStorage(outputMovieDataHandler);
    outputMovieDataHandler = NULL;
    
    // Use QTMovie to flatten
    QTMovie* movie = [[QTMovie alloc] initWithQuickTimeMovie:outputMovie disposeWhenDone:YES error:NULL];
    NSDictionary* dict = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:QTMovieFlatten];
    if (![movie writeToFile:path withAttributes:dict]) {
        fprintf(stderr, "[QTMovie writeToFile:withAttributes] failed\n");
        goto bail;
    }
    
    [movie release];
    outputMovie = NULL;
    
    // Nuke the temp file
    [[NSFileManager defaultManager] removeFileAtPath:(NSString *)tempPath handler:nil];
    CFRelease(tempPath);
    
bail:
    return;
}

@end
