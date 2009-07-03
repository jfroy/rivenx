//
//  RXWorldView.m
//  rivenx
//
//  Created by Jean-Francois Roy on 04/09/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//


#import <OpenGL/CGLMacro.h>
#import <OpenGL/CGLRenderers.h>

#import "Application/RXApplicationDelegate.h"
#import "Base/RXThreadUtilities.h"
#import "Engine/RXWorldProtocol.h"
#import "Utilities/GTMSystemVersion.h"

#import "Rendering/Graphics/RXWorldView.h"

#ifndef kCGLRendererIDMatchingMask
#define kCGLRendererIDMatchingMask   0x00FE7F00
#endif


@interface RXWorldView (RXWorldView_Private)
+ (NSString*)rendererNameForID:(GLint)renderer;

- (void)_createWorkingColorSpace;
- (void)_handleColorProfileChange:(NSNotification*)notification;

- (void)_baseOpenGLStateSetup:(CGLContextObj)cgl_ctx;
- (void)_determineGLVersion:(CGLContextObj)cgl_ctx;
- (void)_determineGLFeatures:(CGLContextObj)cgl_ctx;

- (void)_render:(const CVTimeStamp*)outputTime;
@end


@implementation RXWorldView

static CVReturn rx_render_output_callback(CVDisplayLinkRef displayLink,
                                          const CVTimeStamp* inNow,
                                          const CVTimeStamp* inOutputTime,
                                          CVOptionFlags flagsIn,
                                          CVOptionFlags* flagsOut,
                                          void* ctx)
{
    NSAutoreleasePool* p = [[NSAutoreleasePool alloc] init];
    [(RXWorldView*)ctx _render:inOutputTime];
    [p release];
    return kCVReturnSuccess;
}

static NSOpenGLPixelFormatAttribute windowed_attribs[8] = {
    NSOpenGLPFAWindow,
    NSOpenGLPFADoubleBuffer,
    NSOpenGLPFAColorSize, 24,
    NSOpenGLPFAAlphaSize, 8,
    0
};

+ (BOOL)accessInstanceVariablesDirectly {
    return NO;
}

+ (NSString*)rendererNameForID:(GLint)renderer {
    NSString* renderer_name;
    switch (renderer & kCGLRendererIDMatchingMask) {
        case kCGLRendererGenericID:
            renderer_name = @"Generic";
            break;
        case kCGLRendererGenericFloatID:
            renderer_name = @"Generic Float";
            break;
        case kCGLRendererAppleSWID:
            renderer_name = @"Apple Software";
            break;
        case kCGLRendererATIRage128ID:
            renderer_name = @"ATI Rage 128";
            break;
        case kCGLRendererATIRadeonID:
            renderer_name = @"ATI Radeon";
            break;
        case kCGLRendererATIRageProID:
            renderer_name = @"ATI Rage Pro";
            break;
        case kCGLRendererATIRadeon8500ID:
            renderer_name = @"ATI Radeon 8500";
            break;
        case kCGLRendererATIRadeon9700ID:
            renderer_name = @"ATI Radeon 9700";
            break;
        case kCGLRendererATIRadeonX1000ID:
            renderer_name = @"ATI Radeon X1000";
            break;
        case kCGLRendererATIRadeonX2000ID:
            renderer_name = @"ATI Radeon X2000";
            break;
        case kCGLRendererGeForce2MXID:
            renderer_name = @"NVIDIA GeForce 2MX";
            break;
        case kCGLRendererGeForce3ID:
            renderer_name = @"NVIDIA GeForce 3";
            break;
        case kCGLRendererGeForceFXID:
            renderer_name = @"NVIDIA GeForce FX";
            break;
        case kCGLRendererGeForce8xxxID:
            renderer_name = @"NVIDIA GeForce 8000";
            break;
        case kCGLRendererVTBladeXP2ID:
            renderer_name = @"VT Blade XP2";
            break;
        case kCGLRendererIntel900ID:
            renderer_name = @"Intel 900";
            break;
        case kCGLRendererMesa3DFXID:
            renderer_name = @"Mesa 3DFX";
            break;
        default:
            renderer_name = [NSString stringWithFormat:@"Unknown <%08x>", renderer];
            break;
    }
    
    return renderer_name;
}

- (id)initWithFrame:(NSRect)frame {
    CGLError cgl_err;
    
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
    
    // initialize the global world view reference
    g_worldView = self;
    
    // if we're on Leopard and later, allow offline renderers
    if ([GTMSystemVersion isLeopardOrGreater]) {
        windowed_attribs[4] = NSOpenGLPFAAllowOfflineRenderers;
        windowed_attribs[5] = 0;
    }
    
    // create an NSGL pixel format
    NSOpenGLPixelFormat* format = [[NSOpenGLPixelFormat alloc] initWithAttributes:windowed_attribs];
#if defined(DEBUG)
    GLint npix = [format numberOfVirtualScreens];
    for (GLint ipix = 0; ipix < npix; ipix++) {
        GLint renderer;
        [format getValues:&renderer forAttribute:NSOpenGLPFARendererID forVirtualScreen:ipix];
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"virtual screen %d is driven by the \"%@\" renderer",
            ipix, [RXWorldView rendererNameForID:renderer]);
    }
#endif
    
    // create the render context
    _render_context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
    if (!_render_context) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"could not create the render OpenGL context");
        [self release];
        return nil;
    }
    
    // set the pixel format on the view
    [self setPixelFormat:format];
    [format release];
    
    // cache the underlying CGL pixel format
    _cglPixelFormat = [format CGLPixelFormatObj];
    
    // set the render context on the view
    [self setOpenGLContext:_render_context];
    [_render_context release];
    
    // cache the underlying CGL context
    _render_context_cgl = [_render_context CGLContextObj];
    assert(_render_context_cgl);
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"render context: %p", _render_context_cgl);
    
    // create the state object for the rendering context
    g_renderContextState = [[RXOpenGLState alloc] initWithContext:_render_context_cgl];
    
    // create a load context and pair it with the render context
    _load_context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:_render_context];
    if (!_load_context) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"could not create the resource load OpenGL context");
        [self release];
        return nil;
    }
    
    // cache the underlying CGL context
    _load_context_cgl = [_load_context CGLContextObj];
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"load context: %p", _load_context_cgl);
    
    // set a few context options
    GLint param;
    
    // enable vsync on the render context
    param = 1;
    cgl_err = CGLSetParameter(_render_context_cgl, kCGLCPSwapInterval, &param);
    if (cgl_err != kCGLNoError) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLSetParameter for kCGLCPSwapInterval failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    // disable the MT engine as it is a significant performance hit for Riven X
    cgl_err = CGLDisable(_render_context_cgl, kCGLCEMPEngine);
    if (cgl_err != kCGLNoError) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLEnable for kCGLCEMPEngine failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    cgl_err = CGLDisable(_load_context_cgl, kCGLCEMPEngine);
    if (cgl_err != kCGLNoError) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLEnable for kCGLCEMPEngine failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    // set ourselves as the context data
    cgl_err = CGLSetParameter(_render_context_cgl, kCGLCPClientStorage, (const GLint*)&self);
    if (cgl_err != kCGLNoError) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLSetParameter for kCGLCPClientStorage failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    cgl_err = CGLSetParameter(_load_context_cgl, kCGLCPClientStorage, (const GLint*)&self);
    if (cgl_err != kCGLNoError) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLSetParameter for kCGLCPClientStorage failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    // create the state object for the loading context
    g_loadContextState = [[RXOpenGLState alloc] initWithContext:_load_context_cgl];
    
    // configure the view's autoresizing behavior to resize itself to match its container
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    // do base state setup
    [self _baseOpenGLStateSetup:_load_context_cgl];
    [self _baseOpenGLStateSetup:_render_context_cgl];
    
    // create the CV display link
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, &rx_render_output_callback, self);
    
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
    
    [_render_context release];
    [_load_context release];
    
    CGColorSpaceRelease(_workingColorSpace);
    CGColorSpaceRelease(_displayColorSpace);
    
    [_cursor release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark world view protocol

- (CGLContextObj)renderContext {
    return _render_context_cgl;
}

- (CGLContextObj)loadContext {
    return _load_context_cgl;
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
    
#if defined(DEBUG) && DEBUG > 1
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
#pragma mark view behavior

- (BOOL)isOpaque {
    return YES;
}

- (void)_handleColorProfileChange:(NSNotification*)notification {
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

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    
    // remove ourselves from any previous screen or window related notifications
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:NSWindowDidChangeScreenProfileNotification object:nil];
    
    // get our new window
    NSWindow* w = [self window];
    if (!w)
        return;
    
    // configure our new window
	[w setPreferredBackingLocation:NSWindowBackingLocationVideoMemory];
	[w useOptimizedDrawing:YES];
    
    // register for color profile changes and trigger one artificially
    [center addObserver:self selector:@selector(_handleColorProfileChange:) name:NSWindowDidChangeScreenProfileNotification object:w];
    [self _handleColorProfileChange:nil];
}

- (void)prepareOpenGL {
    if (_glInitialized)
        return;
    _glInitialized = YES;
    
    // generate an update so we look at the OpenGL capabilities
    [self update];
    
    // cache the imp for world render methods
    _renderTarget = [g_world stateCompositor];
    _renderDispatch = RXGetRenderImplementation([_renderTarget class], RXRenderingRenderSelector);
    _postFlushTasksDispatch = RXGetPostFlushTasksImplementation([_renderTarget class], RXRenderingPostFlushTasksSelector);
    
    // start the CV display link
    CVDisplayLinkStart(_displayLink);
}

- (void)update {    
    [super update];
    
    // the virtual screen has changed, reconfigure the contexes and the display link
    
    CGLLockContext(_render_context_cgl);
    CGLLockContext(_load_context_cgl);
    
    if (_displayLink)
        CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, _render_context_cgl, _cglPixelFormat);
    CGLSetVirtualScreen(_load_context_cgl, [_render_context currentVirtualScreen]);
    
    GLint renderer;
    CGLDescribePixelFormat(_cglPixelFormat, [_render_context currentVirtualScreen], kCGLPFARendererID, &renderer);
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"now using virtual screen %d driven by the \"%@\" renderer",
        [_render_context currentVirtualScreen], [RXWorldView rendererNameForID:renderer]);
    
    // determine OpenGL version and features
    [self _determineGLVersion:_render_context_cgl];
    [self _determineGLFeatures:_render_context_cgl];
    
    // FIXME: determine if we need to fallback to software and do so here; this may not be required since we allow fallback in the pixel format
    
    CGLUnlockContext(_load_context_cgl);
    CGLUnlockContext(_render_context_cgl);
}

- (void)reshape {
    if (!_glInitialized || _tornDown)
        return;
    
    float uiScale = ([self window]) ? [[self window] userSpaceScaleFactor] : 1.0F;
    GLint viewportLeft, viewportBottom;
    NSRect glRect;
    
    // calculate the pixel-aligned rectangle in which OpenGL will render. convertRect converts to/from window coordinates when the view argument is nil
    glRect.size = NSIntegralRect([self convertRect:[self bounds] toView:nil]).size;
    glRect.origin = NSPointFromCGPoint(CGPointMake(([self bounds].size.width - glRect.size.width)/2.0,
                                                   ([self bounds].size.height - glRect.size.height)/2.0));
    
    // compute the viewport origin
    viewportLeft = glRect.origin.x > 0 ? -glRect.origin.x * uiScale : 0;
    viewportBottom = glRect.origin.y > 0 ? -glRect.origin.y * uiScale : 0;
    
    _glWidth = glRect.size.width;
    _glHeight = glRect.size.height;
    
    // use the render context because it's the one that matters for screen output
    CGLContextObj cgl_ctx = _render_context_cgl;
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
#pragma mark OpenGL initialization

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

- (void)_determineGLVersion:(CGLContextObj)cgl_ctx {
/*
       The GL_VERSION string begins with a version number.  The version number uses one of these forms:

       major_number.minor_number
       major_number.minor_number.release_number

       Vendor-specific  information  may  follow  the version number. Its  depends on the implementation, but a space
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
    } else
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"unsupported OpenGL major version");
}

- (void)_determineGLFeatures:(CGLContextObj)cgl_ctx {
    NSMutableString* features_message = [[NSMutableString alloc] initWithString:@"supported OpenGL features:\n"];
    NSSet* extensions = [[NSSet alloc] initWithArray:
                         [[NSString stringWithCString:(const char*)glGetString(GL_EXTENSIONS)
                                             encoding:NSASCIIStringEncoding] componentsSeparatedByString:@" "]];
    
    if ([extensions containsObject:@"GL_ARB_texture_rectangle"])
        [features_message appendString:@"    texture rectangle (ARB)\n"];
    if ([extensions containsObject:@"GL_EXT_framebuffer_object"])
        [features_message appendString:@"    framebuffer objects (EXT)\n"];
    if ([extensions containsObject:@"GL_ARB_pixel_buffer_object"])
        [features_message appendString:@"    pixel buffer objects (ARB)\n"];
    if ([extensions containsObject:@"GL_APPLE_vertex_array_object"])
        [features_message appendString:@"    vertex array objects (APPLE)\n"];
    if ([extensions containsObject:@"GL_APPLE_flush_buffer_range"])
        [features_message appendString:@"    flush buffer range (APPLE)\n"];
    
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"%@", features_message);
    
    [extensions release];
    [features_message release];
}

#pragma mark -
#pragma mark rendering

- (void)_render:(const CVTimeStamp*)outputTime {
    if (_tornDown)
        return;
    
    CGLContextObj cgl_ctx = _render_context_cgl;
    CGLSetCurrentContext(cgl_ctx);
    CGLLockContext(cgl_ctx);
    
    // clear to black
    glClear(GL_COLOR_BUFFER_BIT);
    
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
