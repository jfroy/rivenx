//
//	RXCreditsState.m
//	rivenx
//
//	Created by Jean-Francois Roy on 13/12/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <mach/mach.h>
#import <mach/mach_time.h>

#import <OpenGL/CGLMacro.h>
#import <MHKKit/MHKKit.h>

#import "RXCreditsState.h"

static const float kCardViewportBorders[4] = {22.0f, 16.0f, 66.0f, 16.0f};

static const uint16_t kFirstCreditsTextureID = 302;
static const GLuint kCreditsTextureCount = 19;
static const CGSize kCreditsTextureSize = {360.0f, 392.0f};


@implementation RXCreditsState

- (id)init {
	self = [super init];
	
	// initialize a few things for animations
	CVTime displayLinkRP = CVDisplayLinkGetNominalOutputVideoRefreshPeriod([RXGetWorldView() displayLink]);
	_animationPeriod = displayLinkRP.timeValue / (CFTimeInterval)(displayLinkRP.timeScale);
	
	// FIXME: need a new way to get the extra bitmaps archive
	MHKArchive* archive = nil;
	
	// precompute the total storage we'll need because it will yield a far more efficient texture upload
	const size_t textureStorageOffsetStep = kCreditsTextureSize.width * kCreditsTextureSize.height * 4;
	size_t textureStorageSize = kCreditsTextureCount * textureStorageOffsetStep;
	
	// allocate one big chunk of memory for all the textures
	_textureStorage = malloc(textureStorageSize);
	
	// don't need to lock the context since this runs in the main thread
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	
	// save GL state
	glPushAttrib(GL_TEXTURE_BIT);
	glPushClientAttrib(GL_CLIENT_PIXEL_STORE_BIT | GL_CLIENT_VERTEX_ARRAY_BIT);
	
	// create the texture ID array and the textures themselves
	glGenTextures(kCreditsTextureCount, _creditsTextureObjects);
	
	// actually load the textures
	size_t textureStorageOffset = 0;
	GLuint currentTextureIndex = 0;
	for(; currentTextureIndex < kCreditsTextureCount; currentTextureIndex++) {
		[archive loadBitmapWithID:kFirstCreditsTextureID + currentTextureIndex 
						   buffer:BUFFER_OFFSET(_textureStorage, textureStorageOffset) 
						   format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED 
							error:NULL];
		
		// bind the corresponding texture object, configure it and upload the picture
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[currentTextureIndex]);
		
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		
		glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 
					 0, 
					 GL_RGBA, 
					 kCreditsTextureSize.width, 
					 kCreditsTextureSize.height, 
					 0, 
					 GL_BGRA, 
					 GL_UNSIGNED_INT_8_8_8_8_REV, 
					 BUFFER_OFFSET(_textureStorage, textureStorageOffset));
		
		// move along
		textureStorageOffset += textureStorageOffsetStep;
	}
	
	// load up the split texturing shader
	/*_splitTexturingVertexShader = glCreateShaderObjectARB(GL_VERTEX_SHADER_ARB);
	_splitTexturingFragmentShader = glCreateShaderObjectARB(GL_FRAGMENT_SHADER_ARB);
	_splitTexturingProgram = glCreateProgramObjectARB();
	
	glAttachObjectARB(_splitTexturingProgram, _splitTexturingVertexShader);
	glAttachObjectARB(_splitTexturingProgram, _splitTexturingFragmentShader);
	
	glDeleteObjectARB(_splitTexturingVertexShader);
	glDeleteObjectARB(_splitTexturingFragmentShader);
	
	NSString* source = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"split_texturing" ofType:@"vs" inDirectory:@"Shaders"] 
												 encoding:NSASCIIStringEncoding 
													error:NULL];
	const GLcharARB* cSource = [source cStringUsingEncoding:NSASCIIStringEncoding];
	glShaderSourceARB(_splitTexturingVertexShader, 1, &cSource, NULL);
	glCompileShaderARB(_splitTexturingVertexShader);
	
	source = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"split_texturing" ofType:@"fs" inDirectory:@"Shaders"] 
									   encoding:NSASCIIStringEncoding 
										  error:NULL];
	cSource = [source cStringUsingEncoding:NSASCIIStringEncoding];
	glShaderSourceARB(_splitTexturingFragmentShader, 1, &cSource, NULL);
	glCompileShaderARB(_splitTexturingFragmentShader);
	
	glLinkProgramARB(_splitTexturingProgram);*/
#if defined(DEBUG)
	//glValidateProgramARB(_splitTexturingProgram);
#endif

	// restore GL state
	glPopAttrib();
	glPopClientAttrib();
	
	// all the textures are the same size, so we need one set of texture coordinates
	_textureCoordinates[0][0] = 0.0f;
	_textureCoordinates[0][1] = kCreditsTextureSize.height;
	
	_textureCoordinates[0][2] = kCreditsTextureSize.width;
	_textureCoordinates[0][3] = kCreditsTextureSize.height;
	
	_textureCoordinates[0][4] = kCreditsTextureSize.width;
	_textureCoordinates[0][5] = 0.0f;
	
	_textureCoordinates[0][6] = 0.0f;
	_textureCoordinates[0][7] = 0.0f;
	
	memcpy(_textureCoordinates[1], _textureCoordinates[0], sizeof(GLfloat) * 8);
	memcpy(_textureCoordinates[2], _textureCoordinates[0], sizeof(GLfloat) * 8);
	
	// precompute the total height of the "scroll box" (kCreditsTextureCount - 2 + 2)
	_scrollBoxHeight = kCreditsTextureSize.height * 19.0f;
	
	return self;
}

- (void)dealloc {
	// delete the OpenGL texture objects
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];

	// delete the texture objects
	glDeleteTextures(kCreditsTextureCount, _creditsTextureObjects);
	
	// delete the shaders and the program
	//glDeleteObjectARB(_splitTexturingProgram);
	
	// don't bother with OpenGL anymore
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	// now	that the texture objects are gone, we can delete the texture storage area
	free(_textureStorage);
	
	[super dealloc];
}

- (void)_reshapeGL:(NSNotification *)notification {
	// WARNING: IT IS ASSUMED THE CURRENT CONTEXT HAS BEEN LOCKED BY THE CALLER
	CGLContextObj cgl_ctx = CGLGetCurrentContext();
	
#if defined(DEBUG)
	RXOLog(@"%@: reshaping OpenGL", self);
#endif
	
	// compute the credits viewport from the GL viewport and applicable borders
	// FIXME: COMPUTATION IS NOT CORRECT
	_viewportSize = RXGetGLViewportSize();
	_viewportSize.width -= kCardViewportBorders[1] + kCardViewportBorders[3];
	_viewportSize.height -= kCardViewportBorders[0] + kCardViewportBorders[2];
	
	// compute the origin for credit boxes such that they are horizontally centered and below the viewport
	_bottomLeft = CGPointMake(floorf(kCardViewportBorders[1] + (_viewportSize.width / 2.0f) - (kCreditsTextureSize.width / 2.0f)), floorf(kCardViewportBorders[2] - kCreditsTextureSize.height));
	
	// set the scissor test around the credits box
	glScissor(kCardViewportBorders[1], kCardViewportBorders[2], _viewportSize.width, _viewportSize.height);
}

- (void)arm {
	[super arm];
	
	// prepare OpenGL
	CGLContextObj cgl_ctx = CGLGetCurrentContext();
	CGLLockContext(cgl_ctx);
	{
		// we need blending, and glColor at full white
		glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
		
		// disable any bound VBO
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		
		// set the vertex and tex coordinate arrays
		glVertexPointer(2, GL_FLOAT, 0, _textureBoxVertices);
		glTexCoordPointer(2, GL_FLOAT, 0, _textureCoordinates);
		
		[self _reshapeGL:nil];
		
		// start using the split texturing program
		//glUseProgramObjectARB(_splitTexturingProgram);
	}
	CGLUnlockContext(cgl_ctx);
	
	// we need to listen for OpenGL reshape notifications, so we can correct the OpenGL state
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_reshapeGL:) name:@"RXOpenGLDidReshapeNotification" object:nil];
	
	// animation standby
	_animationState = 0;
	_kickOffAnimation = YES;
	_killAnimation = NO;
	
	// and start our lovely animation thread
	[NSThread detachNewThreadSelector:@selector(_animationThreadMain:) toTarget:self withObject:nil];
}

- (void)diffuse {
	// turn off blending and scissor test
	CGLContextObj cgl_ctx = CGLGetCurrentContext();
	CGLLockContext(cgl_ctx);
	{
		// don't bother with OpenGL anymore
		[[NSNotificationCenter defaultCenter] removeObserver:self name:@"RXOpenGLDidReshapeNotification" object:nil];
		
		// stop using the split texturing program
		//glUseProgramObjectARB(0);
	}
	CGLUnlockContext(cgl_ctx);
	
	// kill the animation
	_killAnimation = YES;

	[super diffuse];
}

- (void)_animationThreadMain:(id)object {
	// we need the mach timebase information
	mach_timebase_info_data_t timebase;
	mach_timebase_info(&timebase);
	
	// compute the period in mach time units
	uint64_t animation_period_nanoseconds = _animationPeriod * 1000000000ULL;
	uint64_t animation_period_mach = animation_period_nanoseconds * timebase.denom / timebase.numer;

	while(!_killAnimation) {
		// record the last fire time
		uint64_t now_mach = mach_absolute_time();
		
		// compute how many seconds have elapsed in the current animation state
		CFTimeInterval animation_elapased = ((now_mach - _animationStartTime) * timebase.numer / timebase.denom) / 1000000000.0;
		
		// 302 fade in / out, 303 fade in / out - over 1 second
		if(_animationState == 1 || _animationState == 3 || _animationState == 4 || _animationState == 6) {
			_animationProgress = (GLfloat)animation_elapased;
		}
		
		// 302 display, 303 display - over 5 seconds
		if(_animationState == 2 || _animationState == 5) {
			_animationProgress = (GLfloat)(animation_elapased / 5.0);
		}
		
		// rolling credits, over about 3 minutes (190 seconds)
		if(_animationState == 7) {
			_animationProgress = (GLfloat)(animation_elapased / 190.0);
		}
		
		// if we've reached the end of the current animation state, change state
		if(_animationProgress > 1.0) {
			_animationProgress = 0.0f;
			_animationStartTime = mach_absolute_time();
			_animationState++;
			RXOLog(@"%@: entering animation state %d", self, _animationState);
		}
		
		// if we're reached animation state 8, we're done
		if(_animationState == 8) _killAnimation = YES;
		
		// compute until when we need to sleep
		_lastFireTime = now_mach;
		now_mach = mach_absolute_time();
		uint64_t wake_mach = _lastFireTime + animation_period_mach;
		if(wake_mach > now_mach) mach_wait_until(wake_mach);
	}
	
	[self performSelectorOnMainThread:@selector(diffuse) withObject:nil waitUntilDone:NO];
}

- (CGRect)renderRect {
	return CGRectMake(kCardViewportBorders[1], kCardViewportBorders[2], _viewportSize.width, _viewportSize.height);
}

- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx parent:(id)parent {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD	
	if (_kickOffAnimation) {
		_kickOffAnimation = NO;
		_animationProgress = 2.0f;
	}
	
	if (_animationState == 0) return;
	
	// for the centered stages, one common set of commands to set the coordinates
	if (_animationState < 7) {
		// centered on screen
		_textureBoxVertices[0][0] = _bottomLeft.x;
		_textureBoxVertices[0][1] = kCardViewportBorders[2];
		
		_textureBoxVertices[0][2] = _bottomLeft.x + kCreditsTextureSize.width;
		_textureBoxVertices[0][3] = kCardViewportBorders[2];
		
		_textureBoxVertices[0][4] = _textureBoxVertices[0][2];
		_textureBoxVertices[0][5] = kCardViewportBorders[2] + kCreditsTextureSize.height;
		
		_textureBoxVertices[0][6] = _bottomLeft.x;
		_textureBoxVertices[0][7] = _textureBoxVertices[0][5];
	}
	
	// enable scissor test
	glEnable(GL_SCISSOR_TEST);
	
	// 302 fade in, over 1 second
	if (_animationState == 1) {
		glColor4f(1.0f, 1.0f, 1.0f, _animationProgress);
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[0]);
		glDrawArrays(GL_QUADS, 0, 4);
	}
	
	// 302 display, 5 seconds
	if (_animationState == 2) {
		glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[0]);
		glDrawArrays(GL_QUADS, 0, 4);
	}
	
	// 302 fade out, over 1 second
	if (_animationState == 3) {
		glColor4f(1.0f, 1.0f, 1.0f, 1.0f - _animationProgress);
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[0]);
		glDrawArrays(GL_QUADS, 0, 4);
	}
	
	// 303 fade in, over 1 second
	if (_animationState == 4) {
		glColor4f(1.0f, 1.0f, 1.0f, _animationProgress);
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[1]);
		glDrawArrays(GL_QUADS, 0, 4);
	}
	
	// 303 display, 5 seconds
	if (_animationState == 5) {
		glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[1]);
		glDrawArrays(GL_QUADS, 0, 4);
	}
	
	// 303 fade out, over 1 second
	if (_animationState == 6) {
		glColor4f(1.0f, 1.0f, 1.0f, 1.0f - _animationProgress);
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[1]);
		glDrawArrays(GL_QUADS, 0, 4);
	}
	
	// rolling credits, over about 3 minutes (190 seconds)
	if (_animationState == 7) {
		GLfloat _textureIndexProgress = 19.0f * _animationProgress;
		uint8_t _leadTextureIndex = (uint8_t)lrintf(_textureIndexProgress);
		
		if(_leadTextureIndex == 0) {
			_textureBoxVertices[0][0] = _bottomLeft.x;
			_textureBoxVertices[0][1] = kCardViewportBorders[2] - (kCreditsTextureSize.height * (1.0f - _textureIndexProgress));
			
			_textureBoxVertices[0][2] = _bottomLeft.x + kCreditsTextureSize.width;
			_textureBoxVertices[0][3] = _textureBoxVertices[0][1];
			
			_textureBoxVertices[0][4] = _textureBoxVertices[0][2];
			_textureBoxVertices[0][5] = _textureBoxVertices[0][1] + kCreditsTextureSize.height;
			
			_textureBoxVertices[0][6] = _bottomLeft.x;
			_textureBoxVertices[0][7] = _textureBoxVertices[0][5];
			
			glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
			glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[2 + _leadTextureIndex]);
			glDrawArrays(GL_QUADS, 0, 4);
		}
		
		if (_leadTextureIndex > 0 && _leadTextureIndex < 17) {
			_textureBoxVertices[1][0] = _bottomLeft.x;
			_textureBoxVertices[1][1] = kCardViewportBorders[2] - (kCreditsTextureSize.height * (1.0f - _textureIndexProgress + _leadTextureIndex));
			
			_textureBoxVertices[1][2] = _bottomLeft.x + kCreditsTextureSize.width;
			_textureBoxVertices[1][3] = _textureBoxVertices[1][1];
			
			_textureBoxVertices[1][4] = _textureBoxVertices[1][2];
			_textureBoxVertices[1][5] = _textureBoxVertices[1][1] + kCreditsTextureSize.height;
			
			_textureBoxVertices[1][6] = _bottomLeft.x;
			_textureBoxVertices[1][7] = _textureBoxVertices[1][5];
			
			_textureBoxVertices[0][0] = _bottomLeft.x;
			_textureBoxVertices[0][1] = _textureBoxVertices[1][5];
			
			_textureBoxVertices[0][2] = _bottomLeft.x + kCreditsTextureSize.width;
			_textureBoxVertices[0][3] = _textureBoxVertices[0][1];
			
			_textureBoxVertices[0][4] = _textureBoxVertices[0][2];
			_textureBoxVertices[0][5] = _textureBoxVertices[0][1] + kCreditsTextureSize.height;
			
			_textureBoxVertices[0][6] = _bottomLeft.x;
			_textureBoxVertices[0][7] = _textureBoxVertices[0][5];
			
			glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
			
			glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[1 + _leadTextureIndex]);
			glDrawArrays(GL_QUADS, 0, 4);
			
			glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[2 + _leadTextureIndex]);
			glDrawArrays(GL_QUADS, 4, 4);
		}
		
		if (_leadTextureIndex == 17) {
			_textureBoxVertices[0][0] = _bottomLeft.x;
			_textureBoxVertices[0][1] = kCardViewportBorders[2] - (kCreditsTextureSize.height * (1.0f - _textureIndexProgress + _leadTextureIndex - 1));
			
			_textureBoxVertices[0][2] = _bottomLeft.x + kCreditsTextureSize.width;
			_textureBoxVertices[0][3] = _textureBoxVertices[0][1];
			
			_textureBoxVertices[0][4] = _textureBoxVertices[0][2];
			_textureBoxVertices[0][5] = _textureBoxVertices[0][1] + kCreditsTextureSize.height;
			
			_textureBoxVertices[0][6] = _bottomLeft.x;
			_textureBoxVertices[0][7] = _textureBoxVertices[0][5];
			
			glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
			glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[1 + _leadTextureIndex]);
			glDrawArrays(GL_QUADS, 0, 4);
		}
	}
	
	// disable scissor test
	glDisable(GL_SCISSOR_TEST);
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime parent:(id)parent {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
}

@end
