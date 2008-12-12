//
//	RXMovie.m
//	rivenx
//
//	Created by Jean-Francois Roy on 08/09/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <pthread.h>

#import <OpenGL/CGLMacro.h>
#import <OpenGL/CGLProfilerFunctionEnum.h>
#import <OpenGL/CGLProfiler.h>

#import "RXMovie.h"

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
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"[RXMovie initWithMovie:disposeWhenDone:] MAIN THREAD ONLY" userInfo:nil];
	}
	
	_owner = owner;
	
	OSStatus err = noErr;
	NSError* error = nil;
	
	// bind the movie to a QTMovie
	_movie = [[QTMovie alloc] initWithQuickTimeMovie:movie disposeWhenDone:disposeWhenDone error:&error];
	if (!_movie) {
		[self release];
		@throw [NSException exceptionWithName:@"RXMovieException" reason:@"[QTMovie initWithQuickTimeMovie:disposeWhenDone:error:] failed." userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
	}
	
	// no particular movie hints initially
	_movieHints = 0;
	
	// cache the movie's current size
	[[_movie attributeForKey:QTMovieCurrentSizeAttribute] getValue:&_currentSize];
	
	// pixel buffer attributes
	NSMutableDictionary* pixelBufferAttributes = [NSMutableDictionary new];
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
	
	// if the movie is smaller than 128 bytes in either dimension, create a memory-backed visual context, otherwise go directly to OpenGL
	if (_currentSize.width < 32 || _currentSize.height < 32) {
#if defined(DEBUG)
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"using main memory pixel buffer path");
#endif
		
		err = QTPixelBufferContextCreate(NULL, visualContextOptions, &_visualContext);
		CFRelease(visualContextOptions);
		if (err != noErr) {
			[self release];
			@throw [NSException exceptionWithName:@"RXMovieException" reason:@"QTPixelBufferContextCreate failed." userInfo:[NSDictionary dictionaryWithObject:[NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil] forKey:NSUnderlyingErrorKey]];
		}
		
		// allocate a texture storage buffer and setup a texture object
		_textureStorage = malloc(128 * 128 * 4);
		bzero(_textureStorage, 128 * 128 * 4);
		
		glGenTextures(1, &_glTexture); glReportError();
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _glTexture); glReportError();
		
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_SHARED_APPLE);
		glReportError();
		
		glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, 128, 128, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _textureStorage); glReportError();
	} else {
		err = QTOpenGLTextureContextCreate(NULL, cgl_ctx, pixel_format, visualContextOptions, &_visualContext);
		CFRelease(visualContextOptions);
		if (err != noErr) {
			[self release];
			@throw [NSException exceptionWithName:@"RXMovieException" reason:@"QTOpenGLTextureContextCreate failed." userInfo:[NSDictionary dictionaryWithObject:[NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil] forKey:NSUnderlyingErrorKey]];
		}
	}
	
	// create a VAO and prepare the VA state
	glGenVertexArraysAPPLE(1, &_vao); glReportError();
	[gl_state bindVertexArrayObject:_vao];
	
	glBindBuffer(GL_ARRAY_BUFFER, 0);
	
	glEnableClientState(GL_VERTEX_ARRAY); glReportError();
	glVertexPointer(2, GL_FLOAT, 0, _coordinates); glReportError();
	
	glClientActiveTexture(GL_TEXTURE0);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY); glReportError();
	glTexCoordPointer(2, GL_FLOAT, 0, _coordinates + 8); glReportError();
	
	[gl_state bindVertexArrayObject:0];
	
	CGLUnlockContext(cgl_ctx);
	
	// render at (0, 0), natural size; this will update certain attributes in the visual context
	_renderRect.origin.x = 0.0f;
	_renderRect.origin.y = 0.0f;
	_renderRect.size = _currentSize;
	[self setRenderRect:_renderRect];
	
	// set the movie's visual context
	err = SetMovieVisualContext(movie, _visualContext);
	if (err != noErr) {
		[self release];
		@throw [NSException exceptionWithName:@"RXMovieException" reason:@"SetMovieVisualContext failed." userInfo:[NSDictionary dictionaryWithObject:[NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil] forKey:NSUnderlyingErrorKey]];
	}
	
	// no valid movie texture right now
	_invalidImage = YES;
	
	return self;
}

- (id)initWithURL:(NSURL*)movieURL owner:(id)owner {
	if (!pthread_main_np()) {
		[self release];
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"[RXMovie initWithURL:] MAIN THREAD ONLY" userInfo:nil];
	}
	
	// prepare a property structure
	Boolean active = true;
	Boolean dontAskUnresolved = true;
	Boolean dontInteract = true;
	Boolean async = true;
	Boolean idleImport = true;
//	Boolean optimizations = true;
	_visualContext = NULL;
	QTNewMoviePropertyElement newMovieProperties[] = {
		{kQTPropertyClass_DataLocation, kQTDataLocationPropertyID_CFURL, sizeof(NSURL *), &movieURL, 0},
		{kQTPropertyClass_Context, kQTContextPropertyID_VisualContext, sizeof(QTVisualContextRef), &_visualContext, 0},
		{kQTPropertyClass_NewMovieProperty, kQTNewMoviePropertyID_Active, sizeof(Boolean), &active, 0}, 
		{kQTPropertyClass_NewMovieProperty, kQTNewMoviePropertyID_DontInteractWithUser, sizeof(Boolean), &dontInteract, 0}, 
		{kQTPropertyClass_MovieInstantiation, kQTMovieInstantiationPropertyID_DontAskUnresolvedDataRefs, sizeof(Boolean), &dontAskUnresolved, 0},
		{kQTPropertyClass_MovieInstantiation, kQTMovieInstantiationPropertyID_AsyncOK, sizeof(Boolean), &async, 0},
		{kQTPropertyClass_MovieInstantiation, kQTMovieInstantiationPropertyID_IdleImportOK, sizeof(Boolean), &idleImport, 0},
//		{kQTPropertyClass_MovieInstantiation, kQTMovieInstantiationPropertyID_AllowMediaOptimization, sizeof(Boolean), &optimizations, 0}, LEOPARD ONLY
	};
	
	// try to open the movie
	Movie aMovie = NULL;
	OSStatus err = NewMovieFromProperties(sizeof(newMovieProperties) / sizeof(newMovieProperties[0]), newMovieProperties, 0, NULL, &aMovie);
	if (err != noErr) {
		[self release];
		@throw [NSException exceptionWithName:@"RXMovieException" reason:@"NewMovieFromProperties failed." userInfo:[NSDictionary dictionaryWithObject:[NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil] forKey:NSUnderlyingErrorKey]];
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
	if (!pthread_main_np()) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"[RXMovie dealloc] MAIN THREAD ONLY" userInfo:nil];
	RXOLog2(kRXLoggingRendering, kRXLoggingLevelDebug, @"deallocating");
	
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	CGLLockContext(cgl_ctx);
	
	if (_movie) {
		[_movie stop];
		SetMovieVisualContext([_movie quickTimeMovie], NULL);
		[_movie release];
	}
	
	if (_vao)
		glDeleteVertexArraysAPPLE(1, &_vao);
	if (_visualContext)
		QTVisualContextRelease(_visualContext);
	if (_imageBuffer)
		CFRelease(_imageBuffer);
	if (_glTexture)
		glDeleteTextures(1, &_glTexture);
	if (_textureStorage)
		free(_textureStorage);
	
	CGLUnlockContext(cgl_ctx);
	
	[super dealloc];
}

- (id)owner {
	return _owner;
}

- (QTMovie*)movie {
	return _movie;
}

- (void)setExpectedReadAheadFromDisplayLink:(CVDisplayLinkRef)displayLink {
	CVTime rawOVL = CVDisplayLinkGetOutputVideoLatency(displayLink);
	
	// if the OVL is indefinite, exit
	if (rawOVL.flags | kCVTimeIsIndefinite)
		return;
	
	// set the expected read ahead
	SInt64 ovl = rawOVL.timeValue / rawOVL.timeScale;
	CFNumberRef ovlNumber = CFNumberCreate(NULL, kCFNumberSInt64Type, &ovl);
	QTVisualContextSetAttribute(_visualContext, kQTVisualContextExpectedReadAheadKey, ovlNumber);
	CFRelease(ovlNumber);
}

- (void)setWorkingColorSpace:(CGColorSpaceRef)colorspace {
	QTVisualContextSetAttribute(_visualContext, kQTVisualContextWorkingColorSpaceKey, colorspace);
}

- (void)setOutputColorSpace:(CGColorSpaceRef)colorspace {
	QTVisualContextSetAttribute(_visualContext, kQTVisualContextOutputColorSpaceKey, colorspace);
}

- (BOOL)looping {
	return [[_movie attributeForKey:QTMovieLoopsAttribute] boolValue];
}

- (void)setLooping:(BOOL)flag {
	[_movie setAttribute:[NSNumber numberWithBool:flag] forKey:QTMovieLoopsAttribute];
}

- (void)gotoBeginning {
	[_movie gotoBeginning];
	_invalidImage = YES;
}

- (CGSize)currentSize {
	return _currentSize;
}

- (CGRect)renderRect {
	return _renderRect;
}

- (void)setRenderRect:(CGRect)rect {
	_renderRect = rect;
	
	// update certain visual context attributes
	NSDictionary* attribDict = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:_renderRect.size.width], kQTVisualContextTargetDimensions_WidthKey, [NSNumber numberWithFloat:_renderRect.size.height], kQTVisualContextTargetDimensions_HeightKey, nil];
	QTVisualContextSetAttribute(_visualContext, kQTVisualContextTargetDimensionsKey, attribDict);
	
	// specify video rectangle vertices counter-clockwise from (0, 0)
	_coordinates[0] = _renderRect.origin.x;
	_coordinates[1] = _renderRect.origin.y;
	
	_coordinates[2] = _renderRect.origin.x + _renderRect.size.width;
	_coordinates[3] = _renderRect.origin.y;
	
	_coordinates[4] = _renderRect.origin.x + _renderRect.size.width;
	_coordinates[5] = _renderRect.origin.y + _renderRect.size.height;
	
	_coordinates[6] = _renderRect.origin.x;
	_coordinates[7] = _renderRect.origin.y + _renderRect.size.height;
}

- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx framebuffer:(GLuint)fbo {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	if (!_movie)
		return;
	
	// alias the render context state object pointer
	NSObject<RXOpenGLStateProtocol>* gl_state = g_renderContextState;
	
	// does the visual context have a new image?
	if (QTVisualContextIsNewImageAvailable(_visualContext, outputTime)) {
		// release the old image
		if (_imageBuffer)
			CVPixelBufferRelease(_imageBuffer);
		
		// get the new image
		QTVisualContextCopyImageForTime(_visualContext, kCFAllocatorDefault, outputTime, &_imageBuffer);
		
		// get the current texture's coordinates
		GLfloat* texCoords = _coordinates + 8;
		
		// we may not have copied a valid image (for example, a movie with no video track)
		if (_imageBuffer) {
			if (CFGetTypeID(_imageBuffer) == CVOpenGLTextureGetTypeID()) {
				// get the texture coordinates from the CVOpenGLTexture object and bind its texture object
				CVOpenGLTextureGetCleanTexCoords(_imageBuffer, texCoords, texCoords + 2, texCoords + 4, texCoords + 6);
				glBindTexture(CVOpenGLTextureGetTarget(_imageBuffer), CVOpenGLTextureGetName(_imageBuffer)); glReportError();
			} else {
				GLsizei width = CVPixelBufferGetWidth(_imageBuffer);
				GLsizei height = CVPixelBufferGetHeight(_imageBuffer);
				GLsizei bytesPerRow = CVPixelBufferGetBytesPerRow(_imageBuffer);
				
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
				CVPixelBufferLockBaseAddress(_imageBuffer, 0);
				void* baseAddress = CVPixelBufferGetBaseAddress(_imageBuffer);
				for (GLuint row = 0; row < height; row++)
					memcpy(BUFFER_OFFSET(_textureStorage, (row * 128) << 2), BUFFER_OFFSET(baseAddress, row * bytesPerRow), width << 2);
				CVPixelBufferUnlockBaseAddress(_imageBuffer, 0);
				
				// bind the texture object and update the texture data
				glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _glTexture); glReportError();
				glTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, 0, 0, 128, height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _textureStorage); glReportError();
			}
			
			// mark the texture as valid
			_invalidImage = NO;
		}
	} else if (_imageBuffer) {
		// bind the correct texture object
		// FIXME: ONLY TEXTURE_RECTANGLE_ARB WILL WORK WITH THE CARD SHADER
		if (CFGetTypeID(_imageBuffer) == CVOpenGLTextureGetTypeID())
			glBindTexture(CVOpenGLTextureGetTarget(_imageBuffer), CVOpenGLTextureGetName(_imageBuffer));
		else
			glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _glTexture);
		glReportError();
	}
	
	// do we have an image to render?
	if (_imageBuffer && !_invalidImage) {
		[gl_state bindVertexArrayObject:_vao];
		glDrawArrays(GL_QUADS, 0, 4); glReportError();
	}
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	QTVisualContextTask(_visualContext);
}

@end
