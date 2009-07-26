//
//  RXMovie.m
//  rivenx
//
//  Created by Jean-Francois Roy on 08/09/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import <pthread.h>
#import <limits.h>

#import <OpenGL/CGLMacro.h>

#import "Engine/RXWorldProtocol.h"

#import "RXMovie.h"
#import "Rendering/Audio/RXAudioRenderer.h"


NSString* const RXMoviePlaybackDidEndNotification = @"RXMoviePlaybackDidEndNotification";


@interface RXMovieReaper : NSObject {
@public
    QTMovie* movie;
    QTVisualContextRef vc;
}
@end

@implementation RXMovieReaper

- (void)dealloc {
#if defined(DEBUG)
    RXOLog2(kRXLoggingRendering, kRXLoggingLevelDebug, @"deallocating");
#endif
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
    CGLLockContext(cgl_ctx);
    
    [movie release];
    if (vc)
        QTVisualContextRelease(vc);
    
    CGLUnlockContext(cgl_ctx);
    
    [super dealloc];
}

@end


@implementation RXMovie

+ (BOOL)accessInstanceVariablesDirectly {
    return NO;
}

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithMovie:(Movie)movie disposeWhenDone:(BOOL)disposeWhenDone owner:(id)owner {
    self = [super init];
    if (!self)
        return nil;
    
    // we must be on the main thread to use QuickTime
    if (!pthread_main_np()) {
        [self release];
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"[RXMovie initWithMovie:disposeWhenDone:] MAIN THREAD ONLY"
                                     userInfo:nil];
    }
    
    _owner = owner;
    
    OSStatus err = noErr;
    NSError* error = nil;
    
    // bind the movie to a QTMovie
    _movie = [[QTMovie alloc] initWithQuickTimeMovie:movie disposeWhenDone:disposeWhenDone error:&error];
    if (!_movie) {
        [self release];
        @throw [NSException exceptionWithName:@"RXMovieException"
                                       reason:@"[QTMovie initWithQuickTimeMovie:disposeWhenDone:error:] failed."
                                     userInfo:(error) ? [NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey] : nil];
    }
    
    // no particular movie hints initially
    _hints = 0;
    
    // we do not restrict playback to the selection initially
    [_movie setAttribute:[NSNumber numberWithBool:NO] forKey:QTMoviePlaysSelectionOnlyAttribute];
    _playing_selection = NO;
    
    // cache the movie's current size
    [[_movie attributeForKey:QTMovieCurrentSizeAttribute] getValue:&_current_size];
    
    // cache the movie's original duration
    _original_duration = [_movie duration];
    
    // register for rate change notifications
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleRateChange:) name:QTMovieRateDidChangeNotification object:_movie];
    
    // pixel buffer attributes
    NSMutableDictionary* pixelBufferAttributes = [NSMutableDictionary new];
    [pixelBufferAttributes setObject:[NSNumber numberWithInt:_current_size.width] forKey:(NSString*)kCVPixelBufferWidthKey];
    [pixelBufferAttributes setObject:[NSNumber numberWithInt:_current_size.height] forKey:(NSString*)kCVPixelBufferHeightKey];
    [pixelBufferAttributes setObject:[NSNumber numberWithInt:4] forKey:(NSString*)kCVPixelBufferBytesPerRowAlignmentKey];
    [pixelBufferAttributes setObject:[NSNumber numberWithBool:YES] forKey:(NSString*)kCVPixelBufferOpenGLCompatibilityKey];
#if defined(__LITTLE_ENDIAN__)
    [pixelBufferAttributes setObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
#else
    [pixelBufferAttributes setObject:[NSNumber numberWithInt:kCVPixelFormatType_32ARGB] forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
#endif

    CFMutableDictionaryRef visualContextOptions = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(visualContextOptions, kQTVisualContextPixelBufferAttributesKey, pixelBufferAttributes);
    [pixelBufferAttributes release];
    
    // get the load context and the associated pixel format
    CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
    CGLPixelFormatObj pixel_format = [RXGetWorldView() cglPixelFormat];
    
    // lock the load context
    CGLLockContext(cgl_ctx);
    
    // alias the load context state object pointer
    NSObject<RXOpenGLStateProtocol>* gl_state = g_loadContextState;
    
    // if the movie is smaller than 128 bytes in width, using a main-memory pixel buffer visual context and override the width to 128 bytes
    if (_current_size.width < 32) {
#if defined(DEBUG)
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"using main memory pixel buffer path");
#endif
        
        err = QTPixelBufferContextCreate(NULL, visualContextOptions, &_vc);
        CFRelease(visualContextOptions);
        if (err != noErr) {
            [self release];
            @throw [NSException exceptionWithName:@"RXMovieException"
                                           reason:@"QTPixelBufferContextCreate failed."
                                         userInfo:[NSDictionary dictionaryWithObject:[NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil] forKey:NSUnderlyingErrorKey]];
        }
        
        // allocate a texture storage buffer and setup a texture object
        _texture_storage = malloc(MAX((int)_current_size.width, 128) * (int)_current_size.height << 2);
        bzero(_texture_storage, MAX((int)_current_size.width, 128) * (int)_current_size.height << 2);
        
        glGenTextures(1, &_texture); glReportError();
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _texture); glReportError();
        
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_SHARED_APPLE);
        glReportError();
        
        glTexImage2D(GL_TEXTURE_RECTANGLE_ARB,
                     0,
                     GL_RGBA8,
                     MAX(_current_size.width, 128),
                     _current_size.height,
                     0,
                     GL_BGRA,
#if defined(__LITTLE_ENDIAN__)
                     GL_UNSIGNED_INT_8_8_8_8_REV,
#else
                     GL_UNSIGNED_INT_8_8_8_8_REV,
#endif
                     _texture_storage); glReportError();
    } else {
        err = QTOpenGLTextureContextCreate(NULL, cgl_ctx, pixel_format, visualContextOptions, &_vc);
        CFRelease(visualContextOptions);
        if (err != noErr) {
            [self release];
            @throw [NSException exceptionWithName:@"RXMovieException"
                                           reason:@"QTOpenGLTextureContextCreate failed."
                                         userInfo:[NSDictionary dictionaryWithObject:[NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil] forKey:NSUnderlyingErrorKey]];
        }
    }
    
    // create a VAO and prepare the VA state
    glGenVertexArraysAPPLE(1, &_vao); glReportError();
    [gl_state bindVertexArrayObject:_vao];
    
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    
    glEnableVertexAttribArray(RX_ATTRIB_POSITION); glReportError();
    glVertexAttribPointer(RX_ATTRIB_POSITION, 2, GL_FLOAT, GL_FALSE, 0, _coordinates); glReportError();
    
    glEnableVertexAttribArray(RX_ATTRIB_TEXCOORD0); glReportError();
    glVertexAttribPointer(RX_ATTRIB_TEXCOORD0, 2, GL_FLOAT, GL_FALSE, 0, _coordinates + 8); glReportError();
    
    [gl_state bindVertexArrayObject:0];
    
    CGLUnlockContext(cgl_ctx);
    
    // render at (0, 0), natural size; this will update certain attributes in the visual context
    _render_rect.origin.x = 0.0f;
    _render_rect.origin.y = 0.0f;
    _render_rect.size = _current_size;
    [self setRenderRect:_render_rect];
    
    // set the movie's visual context
    err = SetMovieVisualContext(movie, _vc);
    if (err != noErr) {
        [self release];
        @throw [NSException exceptionWithName:@"RXMovieException"
                                       reason:@"SetMovieVisualContext failed."
                                     userInfo:[NSDictionary dictionaryWithObject:[NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil] forKey:NSUnderlyingErrorKey]];
    }
    
    _current_time_lock = OS_SPINLOCK_INIT;
    _current_time = [_movie currentTime];
    
    _render_lock = OS_SPINLOCK_INIT;
    
    return self;
}

- (id)initWithURL:(NSURL*)movieURL owner:(id)owner {
    if (!pthread_main_np()) {
        [self release];
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"[RXMovie initWithURL:] MAIN THREAD ONLY"
                                     userInfo:nil];
    }
    
    // prepare a property structure
    Boolean active = true;
    Boolean dontAskUnresolved = true;
    Boolean dontInteract = true;
    Boolean async = true;
    Boolean idleImport = true;
//  Boolean optimizations = true;
    
    _vc = NULL;
    QTNewMoviePropertyElement newMovieProperties[] = {
        {kQTPropertyClass_DataLocation, kQTDataLocationPropertyID_CFURL, sizeof(NSURL *), &movieURL, 0},
        {kQTPropertyClass_Context, kQTContextPropertyID_VisualContext, sizeof(QTVisualContextRef), &_vc, 0},
        {kQTPropertyClass_NewMovieProperty, kQTNewMoviePropertyID_Active, sizeof(Boolean), &active, 0}, 
        {kQTPropertyClass_NewMovieProperty, kQTNewMoviePropertyID_DontInteractWithUser, sizeof(Boolean), &dontInteract, 0}, 
        {kQTPropertyClass_MovieInstantiation, kQTMovieInstantiationPropertyID_DontAskUnresolvedDataRefs, sizeof(Boolean), &dontAskUnresolved, 0},
        {kQTPropertyClass_MovieInstantiation, kQTMovieInstantiationPropertyID_AsyncOK, sizeof(Boolean), &async, 0},
        {kQTPropertyClass_MovieInstantiation, kQTMovieInstantiationPropertyID_IdleImportOK, sizeof(Boolean), &idleImport, 0},
//      {kQTPropertyClass_MovieInstantiation, kQTMovieInstantiationPropertyID_AllowMediaOptimization, sizeof(Boolean), &optimizations, 0}, LEOPARD ONLY
    };
    
    // try to open the movie
    Movie aMovie = NULL;
    OSStatus err = NewMovieFromProperties(sizeof(newMovieProperties) / sizeof(newMovieProperties[0]), newMovieProperties, 0, NULL, &aMovie);
    if (err != noErr) {
        [self release];
        @throw [NSException exceptionWithName:@"RXMovieException"
                                       reason:@"NewMovieFromProperties failed."
                                     userInfo:[NSDictionary dictionaryWithObject:[NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil] forKey:NSUnderlyingErrorKey]];
    }
    
    @try {
        return [self initWithMovie:aMovie disposeWhenDone:YES owner:owner];
    } @catch(NSException* e) {
        DisposeMovie(aMovie);
        @throw e;
    }
    
    return self;
}

- (void)dealloc {
#if defined(DEBUG)
    RXOLog2(kRXLoggingRendering, kRXLoggingLevelDebug, @"deallocating");
#endif
    
    OSSpinLockLock(&_render_lock);
    
    CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
    CGLLockContext(cgl_ctx);
    
    if (_vao)
        glDeleteVertexArraysAPPLE(1, &_vao);
    if (_texture)
        glDeleteTextures(1, &_texture);
    if (_texture_storage)
        free(_texture_storage);
    if (_image_buffer)
        CFRelease(_image_buffer);
    
    CGLUnlockContext(cgl_ctx);
    
    if (_movie || _vc) {
        RXMovieReaper* reaper = [RXMovieReaper new];
        reaper->movie = _movie;
        reaper->vc = _vc;
        
        _movie = nil;
        _vc = NULL;
        
        if (!pthread_main_np())
            [reaper performSelectorOnMainThread:@selector(release) withObject:nil waitUntilDone:NO];
        else
            [reaper release];
    }
    
    OSSpinLockUnlock(&_render_lock);
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [super dealloc];
}

- (id)owner {
    return _owner;
}

- (CGSize)currentSize {
    return _current_size;
}

- (QTTime)duration {
    return _original_duration;
}

- (QTTime)videoDuration {
    QTTimeRange track_range = [[[[_movie tracksOfMediaType:QTMediaTypeVideo] objectAtIndex:0] attributeForKey:QTTrackRangeAttribute] QTTimeRangeValue];
    return track_range.duration;
}

- (BOOL)looping {
    return _looping;
}

- (void)setLooping:(BOOL)flag {
    [_movie setAttribute:[NSNumber numberWithBool:flag] forKey:QTMovieLoopsAttribute];
    
    if (flag && !_seamless_looping_hacked) {
        // ladies and gentlemen, because QuickTime fails at life, here is the seamless movie hack
        
        // get the movie's duration
        QTTime duration = [_movie duration];
        
        // find the video and audio tracks; bail out if the movie doesn't have exactly one of each or only one video track
        NSArray* tracks = [_movie tracksOfMediaType:QTMediaTypeVideo];
        if ([tracks count] != 1)
            return;
        QTTrack* video_track = [tracks objectAtIndex:0];
        
        tracks = [_movie tracksOfMediaType:QTMediaTypeSound];
        if ([tracks count] > 1)
            return;
        QTTrack* audio_track = ([tracks count]) ? [tracks objectAtIndex:0] : nil;
        
        TimeValue tv;
        
        // find the movie's last sample time
        GetMovieNextInterestingTime([_movie quickTimeMovie], nextTimeStep | nextTimeEdgeOK, 0, NULL, (TimeValue)duration.timeValue, -1, &tv, NULL);
        assert(GetMoviesError() == noErr);
        
        // find the beginning time of the video track's last sample
        QTTimeRange track_range = [[video_track attributeForKey:QTTrackRangeAttribute] QTTimeRangeValue];
        GetTrackNextInterestingTime([video_track quickTimeTrack], nextTimeStep | nextTimeEdgeOK, (TimeValue)track_range.duration.timeValue, -1, &tv, NULL);
        assert(GetMoviesError() == noErr);
        QTTime video_last_sample_time = QTMakeTime(tv, duration.timeScale);
        
        GetTrackNextInterestingTime([video_track quickTimeTrack], nextTimeStep, tv, -1, &tv, NULL);
        assert(GetMoviesError() == noErr);
        QTTime video_second_last_sample_time = QTMakeTime(tv, duration.timeScale);
        
        // make the movie editable
        [_movie setAttribute:[NSNumber numberWithBool:YES] forKey:QTMovieEditableAttribute];
        
        QTTime last_sample_duration = QTTimeDecrement(duration, video_last_sample_time);
        QTTime second_last_sample_duration = QTTimeDecrement(video_last_sample_time, video_second_last_sample_time);
        
        // loop the video samples using the *last video sample time plus half the last video sample duration* as the duration
        if (QTTimeCompare(last_sample_duration, second_last_sample_duration) == NSOrderedDescending)
            track_range = QTMakeTimeRange(QTZeroTime,
                                          QTTimeIncrement(video_last_sample_time,
                                                          QTMakeTime((duration.timeValue - video_last_sample_time.timeValue) / 2, duration.timeScale)));
        for (int i = 0; i < 300; i++)
            [video_track insertSegmentOfTrack:video_track timeRange:track_range atTime:track_range.duration];
        
        // adjust the original duration to match track_range's duration
        _original_duration = track_range.duration;
        
        // loop the audio samples using the *last video sample time* as the duration
        if (audio_track) {
            track_range = QTMakeTimeRange(QTZeroTime, video_last_sample_time);
            for (int i = 0; i < 300; i++)
                [audio_track insertSegmentOfTrack:audio_track timeRange:track_range atTime:track_range.duration];
        }
        
        // we're done editing the movie
        [_movie setAttribute:[NSNumber numberWithBool:NO] forKey:QTMovieEditableAttribute];
        
        // flag the movie as being hacked for looping
        _seamless_looping_hacked = YES;
        
#if defined(DEBUG)
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"used smooth movie looping hack for %@, original duration=%@",
            self, QTStringFromTime(_original_duration));
#if DEBUG > 2
        [_movie writeToFile:[[NSString stringWithFormat:@"~/Desktop/looping %p.mov", self] stringByExpandingTildeInPath] withAttributes:nil];
#endif
#endif
    }
    
    // update the looping flag
    _looping = flag;
}

- (float)volume {
    return [_movie volume];
}

- (void)setVolume:(float)volume {
#if defined(DEBUG) && DEBUG > 1
    RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"setting volume to %f", volume);
#endif
    
    [_movie setVolume:volume * reinterpret_cast<RX::AudioRenderer*>([g_world audioRenderer])->Gain()];
}

- (BOOL)isPlayingSelection {
    return _playing_selection;
}

- (void)setPlaybackSelection:(QTTimeRange)selection {
    OSSpinLockLock(&_render_lock);
    
    // this method does not clear the current movie image, because it is often
    // used to play a movie in segments (village school, gspit viewer)
    
    // set the movie's current time and selection
    [_movie setCurrentTime:selection.time];
    [_movie setSelection:selection];
    
    // task the VC
    CGLContextObj load_ctx = [RXGetWorldView() loadContext];
    CGLLockContext(load_ctx);
    QTVisualContextTask(_vc);
    CGLUnlockContext(load_ctx);
    
    // disable looping (not sure this is required or desired, but right now selection playback cannot be mixed with looping)
    [self setLooping:NO];
    
    // enable selection playback
    [_movie setAttribute:[NSNumber numberWithBool:YES] forKey:QTMoviePlaysSelectionOnlyAttribute];
    _playing_selection = YES;
    
    OSSpinLockUnlock(&_render_lock);
}

- (void)clearPlaybackSelection {
    [_movie setAttribute:[NSNumber numberWithBool:NO] forKey:QTMoviePlaysSelectionOnlyAttribute];
    _playing_selection = NO;
}

- (void)setExpectedReadAheadFromDisplayLink:(CVDisplayLinkRef)displayLink {
    CVTime rawOVL = CVDisplayLinkGetOutputVideoLatency(displayLink);
    
    // if the OVL is indefinite, exit
    if (rawOVL.flags | kCVTimeIsIndefinite)
        return;
    
    // set the expected read ahead
    SInt64 ovl = rawOVL.timeValue / rawOVL.timeScale;
    CFNumberRef ovlNumber = CFNumberCreate(NULL, kCFNumberSInt64Type, &ovl);
    QTVisualContextSetAttribute(_vc, kQTVisualContextExpectedReadAheadKey, ovlNumber);
    CFRelease(ovlNumber);
}

- (void)setWorkingColorSpace:(CGColorSpaceRef)colorspace {
    QTVisualContextSetAttribute(_vc, kQTVisualContextWorkingColorSpaceKey, colorspace);
}

- (void)setOutputColorSpace:(CGColorSpaceRef)colorspace {
    QTVisualContextSetAttribute(_vc, kQTVisualContextOutputColorSpaceKey, colorspace);
}

- (CGRect)renderRect {
    return _render_rect;
}

- (void)setRenderRect:(CGRect)rect {
    _render_rect = rect;
    
    // update certain visual context attributes
    NSDictionary* attribDict = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithFloat:_render_rect.size.width], kQTVisualContextTargetDimensions_WidthKey,
        [NSNumber numberWithFloat:_render_rect.size.height], kQTVisualContextTargetDimensions_HeightKey,
        nil];
    QTVisualContextSetAttribute(_vc, kQTVisualContextTargetDimensionsKey, attribDict);
    
    // specify video rectangle vertices counter-clockwise from (0, 0)
    _coordinates[0] = _render_rect.origin.x;
    _coordinates[1] = _render_rect.origin.y;
    
    _coordinates[2] = _render_rect.origin.x + _render_rect.size.width;
    _coordinates[3] = _render_rect.origin.y;
    
    _coordinates[4] = _render_rect.origin.x + _render_rect.size.width;
    _coordinates[5] = _render_rect.origin.y + _render_rect.size.height;
    
    _coordinates[6] = _render_rect.origin.x;
    _coordinates[7] = _render_rect.origin.y + _render_rect.size.height;
}

- (void)play {
    [self setRate:1.0f];
}

- (void)stop {
    [_movie stop];
}

- (float)rate {
    return [_movie rate];
}

- (void)setRate:(float)rate {
    [_movie setRate:rate];
}

- (void)_handleRateChange:(NSNotification*)notification {
    // WARNING: MUST RUN ON MAIN THREAD
    float rate = [[[notification userInfo] objectForKey:QTMovieRateDidChangeNotificationParameter] floatValue];
    if (fabsf(rate) < 0.001f)
        [[NSNotificationCenter defaultCenter] postNotificationName:RXMoviePlaybackDidEndNotification object:self];
}

- (void)reset {
#if defined(DEBUG)
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"resetting");
#endif
    
    OSSpinLockLock(&_render_lock);
    
    // release and clear the current image buffer
    CVPixelBufferRelease(_image_buffer);
    _image_buffer = NULL;
    
    // reset the movie to the beginning
    [_movie gotoBeginning];
    
    // update the current time
    OSSpinLockLock(&_current_time_lock);
    _current_time = [_movie currentTime];
    OSSpinLockUnlock(&_current_time_lock);
    
    // task the VC
    CGLContextObj load_ctx = [RXGetWorldView() loadContext];
    CGLLockContext(load_ctx);
    QTVisualContextTask(_vc);
    CGLUnlockContext(load_ctx);
    
    OSSpinLockUnlock(&_render_lock);
}

- (QTTime)_noLockCurrentTime {
    OSSpinLockLock(&_current_time_lock);
    QTTime t = _current_time;
    OSSpinLockUnlock(&_current_time_lock);
    
    t.timeValue = t.timeValue % _original_duration.timeValue;
    return t;
}

- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx framebuffer:(GLuint)fbo {
    // WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
    if (!_movie || !_vc)
        return;
    
    // alias the render context state object pointer
    NSObject<RXOpenGLStateProtocol>* gl_state = g_renderContextState;
    
    OSSpinLockLock(&_render_lock);
    
    // does the visual context have a new image?
    if (QTVisualContextIsNewImageAvailable(_vc, outputTime)) {
        // release the old image
        if (_image_buffer)
            CVPixelBufferRelease(_image_buffer);
        
        // get the new image
        CGLContextObj load_ctx = [RXGetWorldView() loadContext];
        CGLLockContext(load_ctx);
            QTVisualContextCopyImageForTime(_vc, kCFAllocatorDefault, outputTime, &_image_buffer);
        CGLUnlockContext(load_ctx);
        
        // get the current texture's coordinates
        GLfloat* texCoords = _coordinates + 8;
        
        // we may not have copied a valid image (for example, a movie with no video track)
        if (_image_buffer) {
            if (CFGetTypeID(_image_buffer) == CVOpenGLTextureGetTypeID()) {
                // get the texture coordinates from the CVOpenGLTexture object and bind its texture object
                CVOpenGLTextureGetCleanTexCoords(_image_buffer, texCoords, texCoords + 2, texCoords + 4, texCoords + 6);
                glBindTexture(CVOpenGLTextureGetTarget(_image_buffer), CVOpenGLTextureGetName(_image_buffer)); glReportError();
            } else {
                GLsizei width = CVPixelBufferGetWidth(_image_buffer);
                GLsizei height = CVPixelBufferGetHeight(_image_buffer);
                GLsizei bpr = CVPixelBufferGetBytesPerRow(_image_buffer);
                
                // compute texture coordinates
                texCoords[0] = 0.0f;
                texCoords[1] = height;
                
                texCoords[2] = width;
                texCoords[3] = height;
                
                texCoords[4] = width;
                texCoords[5] = 0.0f;
                
                texCoords[6] = 0.0f;
                texCoords[7] = 0.0f;
                
                // marshall the image data into the texture
                CVPixelBufferLockBaseAddress(_image_buffer, 0);
                void* baseAddress = CVPixelBufferGetBaseAddress(_image_buffer);
                for (GLint row = 0; row < height; row++)
                    memcpy(BUFFER_OFFSET(_texture_storage, (row * MAX((GLint)_current_size.width, 128)) << 2),
                           BUFFER_OFFSET(baseAddress, row * bpr),
                           width << 2);
                CVPixelBufferUnlockBaseAddress(_image_buffer, 0);
                
                // bind the texture object and update the texture data
                glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _texture); glReportError();
                
                glTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB,
                                0,
                                0,
                                0,
                                MAX(_current_size.width, 128),
                                height,
                                GL_BGRA,
#if defined(__LITTLE_ENDIAN__)
                                GL_UNSIGNED_INT_8_8_8_8_REV,
#else
                                GL_UNSIGNED_INT_8_8_8_8_REV,
#endif
                                _texture_storage); glReportError();
            }
        }
    } else if (_image_buffer) {
        // bind the correct texture object
        if (CFGetTypeID(_image_buffer) == CVOpenGLTextureGetTypeID()) {
            assert(CVOpenGLTextureGetTarget(_image_buffer) == GL_TEXTURE_RECTANGLE_ARB);
            glBindTexture(CVOpenGLTextureGetTarget(_image_buffer), CVOpenGLTextureGetName(_image_buffer));
        } else
            glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _texture);
        glReportError();
    }
    
    // do we have an image to render?
    if (_image_buffer) {
        [gl_state bindVertexArrayObject:_vao];
        glDrawArrays(GL_QUADS, 0, 4); glReportError();
    }
    
    OSSpinLockUnlock(&_render_lock);
    
    // update the current time
    OSSpinLockLock(&_current_time_lock);
    _current_time = [_movie currentTime];
    OSSpinLockUnlock(&_current_time_lock);
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime {
    // WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
    CGLContextObj load_ctx = [RXGetWorldView() loadContext];
    CGLLockContext(load_ctx);
    QTVisualContextTask(_vc);
    CGLUnlockContext(load_ctx);
}

@end
