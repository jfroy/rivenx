//
//	RXWorldView.m
//	rivenx
//
//	Created by Jean-Francois Roy on 04/09/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//


#import <OpenGL/CGLMacro.h>

#import "RXWorldView.h"
#import "RXWorldProtocol.h"
#import "RXThreadUtilities.h"
#import "RXApplicationDelegate.h"


@interface RXWorldView (RXWorldView_Private)
- (void)_createWorkingColorSpace;
- (void)_displayProfileChanged:(NSNotification *)notification;
- (void)_baseOpenGLStateSetup:(CGLContextObj)cgl_ctx;
- (void)_determineGLVersion:(CGLContextObj)cgl_ctx;
- (void)_determineGLFeatures:(CGLContextObj)cgl_ctx;
- (void)_render:(const CVTimeStamp*)outputTime;
@end


@implementation RXWorldView

static CVReturn _rx_render_output_callback(CVDisplayLinkRef displayLink,
										   const CVTimeStamp* inNow,
										   const CVTimeStamp* inOutputTime,
										   CVOptionFlags flagsIn,
										   CVOptionFlags* flagsOut,
										   void* displayLinkContext)
{
	NSAutoreleasePool* p = [[NSAutoreleasePool alloc] init];
	
	if (![(RXWorldView *)displayLinkContext lockFocusIfCanDraw])
		goto end_outout_callback;
	
	[(RXWorldView *)displayLinkContext _render:inOutputTime];
	[(RXWorldView *)displayLinkContext unlockFocus];
	
end_outout_callback:
	[p release];
	return kCVReturnSuccess;
}

static CVReturn _rx_render_setup_output_callback(CVDisplayLinkRef displayLink,
												 const CVTimeStamp* inNow,
												 const CVTimeStamp* inOutputTime,
												 CVOptionFlags flagsIn,
												 CVOptionFlags* flagsOut,
												 void* displayLinkContext)
{
	CGLSetCurrentContext([(RXWorldView *)displayLinkContext renderContext]);
	RXSetThreadNameC("Rendering");
	CVDisplayLinkSetOutputCallback(displayLink, &_rx_render_output_callback, displayLinkContext);
	return kCVReturnSuccess;
}

static NSOpenGLPixelFormatAttribute windowed_fsaa_attribs[] = {
	NSOpenGLPFAWindow,
	NSOpenGLPFAAccelerated,
	NSOpenGLPFANoRecovery,
	NSOpenGLPFADoubleBuffer,
	NSOpenGLPFAColorSize, 24,
	NSOpenGLPFAAlphaSize, 8,
	NSOpenGLPFADepthSize, 24,
	NSOpenGLPFASampleBuffers, 1,
	NSOpenGLPFASamples, 4,
	NSOpenGLPFASampleAlpha,
	NSOpenGLPFAMultisample,
	0
};

static NSOpenGLPixelFormatAttribute windowed_no_fsaa_attribs[] = {
	NSOpenGLPFAWindow,
	NSOpenGLPFAAccelerated,
	NSOpenGLPFANoRecovery,
	NSOpenGLPFADoubleBuffer,
	NSOpenGLPFAColorSize, 24,
	NSOpenGLPFAAlphaSize, 8,
	NSOpenGLPFADepthSize, 24,
	0
};

+ (BOOL)accessInstanceVariablesDirectly {
	return NO;
}

- (id)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	
	// initialize the global world view reference
	g_worldView = self;
	
	// create an NSGL pixel format and then a context
	NSOpenGLPixelFormat* format = [[NSOpenGLPixelFormat alloc] initWithAttributes:windowed_fsaa_attribs];
	_renderContext = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
	
	// failed, try the no-FSAA format attributes
	if (!_renderContext) {
		[format release];
		format = [[NSOpenGLPixelFormat alloc] initWithAttributes:windowed_no_fsaa_attribs];
		_renderContext = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
	}
	
	// still failed, bail
	if (!_renderContext) {
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"could not create the render OpenGL context");
		[self release];
		return nil;
	}
	
	// set the pixel format on the view
	[self setPixelFormat:format];
	[format release];
	
	// cache the CGL pixel format object
	_cglPixelFormat = [format CGLPixelFormatObj];
	
	// set the render context on the view
	[self setOpenGLContext:_renderContext];
	
	// cache the underlying CGL context
	_renderCGLContext = [_renderContext CGLContextObj];
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"render context: %p", _renderCGLContext);
	
	// create the state object for the rendering context
	g_renderContextState = [[RXOpenGLState alloc] initWithContext:_renderCGLContext];
	
	// create a load context and pair it with the render context
	_loadContext = [[NSOpenGLContext alloc] initWithFormat:format shareContext:_renderContext];
	if (!_loadContext) {
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"could not create the resource load OpenGL context");
		[self release];
		return nil;
	}
	
	// cache the underlying CGL objects
	_loadCGLContext = [_loadContext CGLContextObj];
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"load context: %p", _loadCGLContext);
	
	// create the state object for the loading context
	g_loadContextState = [[RXOpenGLState alloc] initWithContext:_loadCGLContext];
	
	// do base state setup for the load context
	[self _baseOpenGLStateSetup:_loadCGLContext];
	
	CGLError cglErr;
	
	// set ourselves as the context's user context data
	cglErr = CGLSetParameter(_renderCGLContext, kCGLCPClientStorage, (const GLint *)&self);
	if (cglErr != kCGLNoError) {
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLSetParameter for kCGLCPClientStorage failed with error %d: %s", cglErr, CGLErrorString(cglErr));
		[self release];
		return nil;
	}
	
	// set ourselves as the context's user context data
	cglErr = CGLSetParameter(_loadCGLContext, kCGLCPClientStorage, (const GLint *)&self);
	if (cglErr != kCGLNoError) {
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLSetParameter for kCGLCPClientStorage failed with error %d: %s", cglErr, CGLErrorString(cglErr));
		[self release];
		return nil;
	}
	
	// sync to VBL
	GLint swapInterval = 1;
	cglErr = CGLSetParameter(_renderCGLContext, kCGLCPSwapInterval, &swapInterval);
	if (cglErr != kCGLNoError)
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLSetParameter for kCGLCPSwapInterval failed with error %d: %s", cglErr, CGLErrorString(cglErr));
	
	// working color space
	_workingColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
	
	// get the default cursor from the world
	_cursor = [[g_world defaultCursor] retain];
	
	// cache the height of the menu bar, since it will change if / when the menu bar is hidden
	_menuBarHeight = [[NSApp mainMenu] menuBarHeight];
	
	return self;
}

- (void)tearDown {
	if (_tornDown)
		return;
	_tornDown = YES;
#if defined(DEBUG)
	RXOLog(@"tearing down");
#endif	
	
	// terminate notifications
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	// terminate the dislay link
	if (_displayLink)
		CVDisplayLinkStop(_displayLink);
}

- (void)dealloc {
	[self tearDown];
	
	if (_displayLink)
		CVDisplayLinkRelease(_displayLink);
	
	[_renderContext release];
	[_loadContext release];
	
	CGColorSpaceRelease(_workingColorSpace);
	CGColorSpaceRelease(_displayColorSpace);
	
	[_cursor release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark world view protocol

- (CGLContextObj)renderContext {
	return _renderCGLContext;
}

- (CGLContextObj)loadContext {
	return _loadCGLContext;
}

- (CGLPixelFormatObj)cglPixelFormat {
	return _cglPixelFormat;
}

- (CVDisplayLinkRef)displayLink {
	return _displayLink;
}

- (CGColorSpaceRef)workingColorSpace {
	return _workingColorSpace;
}

- (CGColorSpaceRef)displayColorSpace {
	return _displayColorSpace;
}

- (rx_size_t)viewportSize {
	return RXSizeMake(_glWidth, _glHeight);
}

- (NSCursor*)cursor {
	return _cursor;
}

- (void)setCursor:(NSCursor*)cursor {
	// NSCursor instances are immutable
	if (cursor == _cursor)
		return;
	
	// the rest of this method must run on the main thread
	if (!pthread_main_np()) {
		[self performSelectorOnMainThread:@selector(setCursor:) withObject:cursor waitUntilDone:NO];
		return;
	}
	
#if defined(DEBUG)
	if (cursor == [g_world defaultCursor])
		RXOLog2(kRXLoggingEvents, kRXLoggingLevelDebug, @"setting cursor to default cursor");
	else if (cursor == [g_world openHandCursor])
		RXOLog2(kRXLoggingEvents, kRXLoggingLevelDebug, @"setting cursor to open hand cursor");
	else
		RXOLog2(kRXLoggingEvents, kRXLoggingLevelDebug, @"setting cursor to %@", cursor);
#endif
	
	NSCursor* old = _cursor;
	_cursor = [cursor retain];
	[old release];
	
	[_cursor set];
	[[self window] invalidateCursorRectsForView:self];
}

#pragma mark -
#pragma mark event handling

// we need to forward events to the state compositor, which will forward them to the rendering states

- (BOOL)acceptsFirstResponder {
	return YES;
}

- (BOOL)becomeFirstResponder {
	return YES;
}

- (void)mouseDown:(NSEvent *)theEvent {
	[[g_world stateCompositor] mouseDown:theEvent];
}

- (void)mouseUp:(NSEvent *)theEvent {
	[[g_world stateCompositor] mouseUp:theEvent];
}

- (void)mouseMoved:(NSEvent *)theEvent {
	NSPoint screenLoc = [self convertPoint:[theEvent locationInWindow] toView:nil];
	
	// if we're in fullscreen mode and on the main display, we have to check if we're over the menu bar
	if ([[NSApp delegate] isFullscreen]) {
		CGDirectDisplayID ddid = CVDisplayLinkGetCurrentCGDisplay(_displayLink);
		CGDirectDisplayID mainDisplay = CGMainDisplayID();
		if (ddid == mainDisplay) {
			CGRect displayBounds = CGDisplayBounds(ddid);
			if (screenLoc.y < displayBounds.size.height - _menuBarHeight) {
				if ([NSMenu menuBarVisible]) {
					[NSMenu setMenuBarVisible:NO];
					
					// restore our cursor
					[_cursor set];
				}
			} else {
				if (![NSMenu menuBarVisible]) {
					[NSMenu setMenuBarVisible:YES];
					
					// while over the menu bar, use the system's arrow cursor
					[[NSCursor arrowCursor] set];
				}
			}
		}
	}
	
	// forward the even to the state compositor
	[[g_world stateCompositor] mouseMoved:theEvent];
}

- (void)mouseDragged:(NSEvent *)theEvent {
	[[g_world stateCompositor] mouseDragged:theEvent];
}

- (void)keyDown:(NSEvent *)theEvent {
	[[g_world stateCompositor] keyDown:theEvent];
}

- (void)resetCursorRects {
	[self addCursorRect:[self bounds] cursor:_cursor];
	[_cursor setOnMouseEntered:YES];
}

#pragma mark -

- (BOOL)isOpaque {
	return YES;
}

- (BOOL)lockFocusIfCanDraw {
	BOOL canDraw = [super lockFocusIfCanDraw];
	if (canDraw && [[self openGLContext] view] != self)
		[[self openGLContext] setView:self];
	return canDraw;
}

- (void)viewWillMoveToWindow:(NSWindow*)newWindow {
	NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
	[center removeObserver:self name:NSWindowDidChangeScreenProfileNotification object:nil];
	
	if (newWindow) {
		[center addObserver:self selector:@selector(_displayProfileChanged:) name:NSWindowDidChangeScreenProfileNotification object:newWindow];
		[self _displayProfileChanged:nil];
	}
	
	[super viewWillMoveToWindow:newWindow];
}

- (void)_baseOpenGLStateSetup:(CGLContextObj)cgl_ctx {	
	// set background color to black
#if defined(DEBUG)
	glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
#else
	glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
#endif
	
	// disable most features that we don't need
	glDisable(GL_BLEND);
	glDisable(GL_CULL_FACE);
	glDisable(GL_DITHER);
	glDisable(GL_LIGHTING);
	glDisable(GL_ALPHA_TEST);
	glDisable(GL_DEPTH_TEST);
	glDisable(GL_SCISSOR_TEST);
	if (GLEE_ARB_multisample)
		glDisable(GL_MULTISAMPLE_ARB);
	
	// pixel store state
	glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
	
	// framebuffer masks
	glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
	glDepthMask(GL_FALSE);
	glStencilMask(GL_FALSE);
	
	// hints
	glHint(GL_POINT_SMOOTH_HINT, GL_NICEST);
	glHint(GL_LINE_SMOOTH_HINT, GL_NICEST);
	glHint(GL_POLYGON_SMOOTH_HINT, GL_NICEST);
	glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);
	glHint(GL_FOG_HINT, GL_NICEST);
	if (GLEE_APPLE_transform_hint)
		glHint(GL_TRANSFORM_HINT_APPLE, GL_NICEST);
	
	glReportError();
}

- (void)prepareOpenGL {
	if (_glInitialized)
		return;
	_glInitialized = YES;

#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"preparing OpenGL");
#endif
		
	// autoresize mode
	[self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	
	// cache the imp for world render methods
	_renderTarget = [g_world stateCompositor];
	_renderDispatch = RXGetRenderImplementation([_renderTarget class], RXRenderingRenderSelector);
	_postFlushTasksDispatch = RXGetPostFlushTasksImplementation([_renderTarget class], RXRenderingPostFlushTasksSelector);
	
	// determine OpenGL version and features
	[self _determineGLVersion:_renderCGLContext];
	
	// do base OpenGL state setup for the render context
	[self _baseOpenGLStateSetup:_renderCGLContext];
	
	// make sure the viewport is setup correctly
	[self reshape];
	
	// setup and start the CV display link
	CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
	CVDisplayLinkSetOutputCallback(_displayLink, &_rx_render_setup_output_callback, self);
	CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, _renderCGLContext, _cglPixelFormat);
	CVDisplayLinkStart(_displayLink);
}

- (void)update {
	[super update];
	[_loadContext update];
}

- (void)reshape {
	if (!_glInitialized || _tornDown)
		return;
	
	float uiScale = ([self window]) ? [[self window] userSpaceScaleFactor] : 1.0F;
	GLint viewportLeft, viewportBottom;
	NSRect glRect;
	
	// calculate the pixel-aligned rectangle in which OpenGL will render. convertRect converts to/from window coordinates when the view argument is nil
	glRect.size = NSIntegralRect([self convertRect:[self bounds] toView:nil]).size;
	glRect.origin = NSPointFromCGPoint(CGPointMake(([self bounds].size.width - glRect.size.width)/2.0, ([self bounds].size.height - glRect.size.height)/2.0));
	
	// compute the viewport origin
	viewportLeft = glRect.origin.x > 0 ? -glRect.origin.x * uiScale : 0;
	viewportBottom = glRect.origin.y > 0 ? -glRect.origin.y * uiScale : 0;
	
	_glWidth = glRect.size.width;
	_glHeight = glRect.size.height;
	
	// use the render context because it's the one that matters for screen output
	CGLContextObj CGL_MACRO_CONTEXT = _renderCGLContext;
	CGLLockContext(cgl_ctx);
	
	// set the OpenGL viewport
	glViewport(viewportLeft, viewportBottom, _glWidth, _glHeight);
	
	// set up our coordinate system with lower-left at (0, 0) and upper-right at (_glWidth, _glHeight)
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glOrtho(0.0, _glWidth, 0.0, _glHeight, 0.0, 1.0);
	
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();
	
	glReportError();
	
	// let others re-configure OpenGL to their needs
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"sending RXOpenGLDidReshapeNotification notification");
#endif
	[[NSNotificationCenter defaultCenter] postNotificationName:@"RXOpenGLDidReshapeNotification" object:self];
	
	CGLUnlockContext(cgl_ctx);
}

#pragma mark -

- (void)_displayProfileChanged:(NSNotification *)notification {
	CGDirectDisplayID ddid = CVDisplayLinkGetCurrentCGDisplay(_displayLink);
	CMProfileRef displayProfile;
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"updating display colorspace");
#endif
	
	// ask ColorSync for our current display's profile
	CMGetProfileByAVID((CMDisplayIDType)ddid, &displayProfile);
	if (_displayColorSpace)
		CGColorSpaceRelease(_displayColorSpace);
	
	_displayColorSpace = CGColorSpaceCreateWithPlatformColorSpace(displayProfile);
	CMCloseProfile(displayProfile);
}

- (void)_determineGLVersion:(CGLContextObj)cgl_ctx {
/*
	   The GL_VERSION string begins with a version number.	The version number uses one of these forms:

	   major_number.minor_number
	   major_number.minor_number.release_number

	   Vendor-specific	information	 may  follow  the version number. Its  depends on the implementation, but a space
	   always separates the version number and the vendor-specific information.
*/
	const GLubyte* glVersionString = glGetString(GL_VERSION); glReportError();
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"GL_VERSION: %s", glVersionString);
	
	GLubyte* minorVersionString;
	_glMajorVersion = (GLuint)strtol((const char*)glVersionString, (char**)&minorVersionString, 10);
	_glMinorVersion = (GLuint)strtol((const char*)minorVersionString + 1, NULL, 10);
	
	// GLSL is somewhat more complicated than mere extensions
	if (_glMajorVersion == 1) {
		const GLubyte* extensions = glGetString(GL_EXTENSIONS); glReportError();
		
		if (gluCheckExtension((const GLubyte *) "GL_ARB_shader_objects", extensions) &&
			gluCheckExtension((const GLubyte *) "GL_ARB_vertex_shader", extensions) &&
			gluCheckExtension((const GLubyte *) "GL_ARB_fragment_shader", extensions))
		{
			if (gluCheckExtension((const GLubyte *) "GL_ARB_shading_language_110", extensions)) {
				_glslMajorVersion = 1;
				_glslMinorVersion = 1;
			} else if (gluCheckExtension((const GLubyte *) "GL_ARB_shading_language_100", extensions)) {
				_glslMajorVersion = 1;
				_glslMinorVersion = 0;
			}
		} else {
			_glslMajorVersion = 0;
			_glslMinorVersion = 0;
		}
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"Computed GLSL version: %u.%u", _glslMajorVersion, _glslMinorVersion);
	} else if (_glMajorVersion == 2) {
/*
The GL_VERSION and GL_SHADING_LANGUAGE_VERSION strings begin with a version number. The version number uses one of these forms:

major_number.minor_number major_number.minor_number.release_number
*/		
		const GLubyte* glslVersionString = glGetString(GL_SHADING_LANGUAGE_VERSION); glReportError();
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"GL_SHADING_LANGUAGE_VERSION: %s", glVersionString);
		
		GLubyte* minorVersionString;
		_glslMajorVersion = (GLuint)strtol((const char*)glslVersionString, (char**)&minorVersionString, 10);
		_glslMinorVersion = (GLuint)strtol((const char*)minorVersionString + 1, NULL, 10);
	} else {
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"unsupported OpenGL major version");
		return;
	}
	
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"GL_EXTENSIONS: %s", glGetString(GL_EXTENSIONS));
}

- (void)_determineGLFeatures:(CGLContextObj)cgl_ctx {
	// FIXME: implement _determineGLFeatures
}

- (void)_render:(const CVTimeStamp*)outputTime {
	if (_tornDown)
		return;
	
	CGLContextObj CGL_MACRO_CONTEXT = _renderCGLContext;
	CGLLockContext(cgl_ctx);
	
	// clear to black
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	
	// render the world
	_renderDispatch.imp(_renderTarget, _renderDispatch.sel, outputTime, cgl_ctx, 0);
	
	// glFlush and swap the front and back buffers
	CGLFlushDrawable(cgl_ctx);
	
	// let the world perform post-flush processing
	_postFlushTasksDispatch.imp(_renderTarget, _postFlushTasksDispatch.sel, outputTime);
	
	CGLUnlockContext(cgl_ctx);
}

- (void)drawRect:(NSRect)rect {

}

@end
