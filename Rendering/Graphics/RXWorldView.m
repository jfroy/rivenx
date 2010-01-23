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
- (void)_updateTotalVRAM;

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

static NSOpenGLPixelFormatAttribute base_window_attribs[] = {
    NSOpenGLPFAWindow,
    NSOpenGLPFADoubleBuffer,
    NSOpenGLPFAColorSize, 24,
    NSOpenGLPFAAlphaSize, 8,
};

static NSString* required_extensions[] = {
    @"GL_APPLE_vertex_array_object",
    @"GL_ARB_texture_rectangle",
    @"GL_ARB_pixel_buffer_object",
    @"GL_EXT_framebuffer_object",
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
    assert(g_worldView == nil);
    g_worldView = self;
    
    // prepare the generic "no supported GPU" error
    NSDictionary* error_info = [NSDictionary dictionaryWithObjectsAndKeys:
        NSLocalizedStringFromTable(@"NO_SUPPORTED_GPU", @"Rendering", @"no supported gpu"), NSLocalizedDescriptionKey,
        NSLocalizedStringFromTable(@"UPGRADE_OS_OR_HARDWARE", @"Rendering", @"upgrade Mac OS X or computer or gpu"), NSLocalizedRecoverySuggestionErrorKey,
        [NSArray arrayWithObjects:NSLocalizedString(@"QUIT", @"quit"), nil], NSLocalizedRecoveryOptionsErrorKey,
        [NSApp delegate], NSRecoveryAttempterErrorKey,
        nil];
    NSError* no_supported_gpu_error = [NSError errorWithDomain:RXErrorDomain code:kRXErrFailedToCreatePixelFormat userInfo:error_info];
    
    // process the basic pixel format attributes to a final list of attributes
    NSOpenGLPixelFormatAttribute final_attribs[32] = {0};
    uint32_t pfa_index = sizeof(base_window_attribs) / sizeof(NSOpenGLPixelFormatAttribute) - 1;
    
    // copy the basic attributes
    memcpy(final_attribs, base_window_attribs, sizeof(base_window_attribs));
    
    // if we're on Leopard and later, allow offline renderers
    if ([GTMSystemVersion isLeopardOrGreater])
        final_attribs[++pfa_index] = NSOpenGLPFAAllowOfflineRenderers;
    
    // request a 4x MSAA multisampling buffer by default (if context creation fails, we'll remove those)
    final_attribs[++pfa_index] = NSOpenGLPFASampleBuffers;
    final_attribs[++pfa_index] = 1;
    final_attribs[++pfa_index] = NSOpenGLPFASamples;
    final_attribs[++pfa_index] = 4;
    final_attribs[++pfa_index] = NSOpenGLPFAMultisample;
    final_attribs[++pfa_index] = NSOpenGLPFASampleAlpha;
    
//#define SIMULATE_NO_PF 1
#if SIMULATE_NO_PF
    final_attribs[++pfa_index] = NSOpenGLPFARendererID;
    final_attribs[++pfa_index] = 0xcafebabe;
#endif
    
    // terminate the list of attributes
    final_attribs[++pfa_index] = 0;
    
    // create an NSGL pixel format
    NSOpenGLPixelFormat* format = [[NSOpenGLPixelFormat alloc] initWithAttributes:final_attribs];
    if (!format) {
        // remove the multisampling buffer attributes
        pfa_index = sizeof(base_window_attribs) / sizeof(NSOpenGLPixelFormatAttribute);
        
#if SIMULATE_NO_PF
        final_attribs[++pfa_index] = NSOpenGLPFARendererID;
        final_attribs[++pfa_index] = 0xcafebabe;
#endif
        
        final_attribs[++pfa_index] = 0;
        
        format = [[NSOpenGLPixelFormat alloc] initWithAttributes:final_attribs];
        if (!format) {
            [NSApp presentError:no_supported_gpu_error];
            [self release];
            return nil;
        }
    }
    
    // iterate over the virtual screens to determine the set of virtual screens / renderers we can actually use
    NSMutableSet* viable_renderers = [NSMutableSet set];
    
    NSSet* required_extensions_set = [NSSet setWithObjects:required_extensions count:sizeof(required_extensions) / sizeof(NSString*)];
    NSOpenGLContext* probing_context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
    GLint npix = [format numberOfVirtualScreens];
    for (GLint ipix = 0; ipix < npix; ipix++) {
        GLint renderer;
        [format getValues:&renderer forAttribute:NSOpenGLPFARendererID forVirtualScreen:ipix];
        
        [probing_context makeCurrentContext];
        [probing_context setCurrentVirtualScreen:ipix];
        
#if DEBUG
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"virtual screen %d is driven by the \"%@\" renderer",
            ipix, [RXWorldView rendererNameForID:renderer]);
#endif
        
        [self _determineGLVersion:[probing_context CGLContextObj]];
        [self _determineGLFeatures:[probing_context CGLContextObj]];
        
        NSMutableSet* missing_extensions = [[required_extensions_set mutableCopy] autorelease];
        [missing_extensions minusSet:_gl_extensions];
        if ([missing_extensions count] == 0) {
//#define FORCE_GENERIC_FLOAT_RENDERER 1
#if FORCE_GENERIC_FLOAT_RENDERER
            if ((renderer & kCGLRendererIDMatchingMask) == kCGLRendererGenericFloatID)
#endif
                [viable_renderers addObject:[NSNumber numberWithInt:renderer]];
        }
    }
    [NSOpenGLContext clearCurrentContext];
    [probing_context release];
    
//#define SIMULATE_NO_VIABLE_RENDERER 1
#if SIMULATE_NO_VIABLE_RENDERER
    [viable_renderers removeAllObjects];
#endif
    
    // if there are no viable renderers, bail out
    if ([viable_renderers count] == 0) {
        [format release];
        
        [NSApp presentError:no_supported_gpu_error];
        [self release];
        return nil;
    }
    
    // if there is only one viable renderer, we'll force it in the final pixel format
    else if ([viable_renderers count] == 1) {
        final_attribs[pfa_index] = NSOpenGLPFARendererID;
        final_attribs[++pfa_index] = [[viable_renderers anyObject] intValue];
        
        final_attribs[++pfa_index] = 0;
        
        [format release];
        format = [[NSOpenGLPixelFormat alloc] initWithAttributes:final_attribs];
        if (!format) {
            [NSApp presentError:no_supported_gpu_error];
            [self release];
            return nil;
        }
    }
    // NOTE: ignoring the case where [viable_renderers count] != [format numberOfVirtualScreens], for now
    
    // set the pixel format on the view
    [self setPixelFormat:format];
    [format release];
    
    // create the render context
    _render_context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
    if (!_render_context) {
        // NSOpenGLPFARendererID, kCGLRendererGenericFloatID,
        
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"could not create the render OpenGL context");
        [self release];
        return nil;
    }
    
    // cache the underlying CGL pixel format
    _cglPixelFormat = [format CGLPixelFormatObj];
    
    // set the render context on the view and release it (e.g. transfer ownership to the view)
    [self setOpenGLContext:_render_context];
    [_render_context release];
    
    // cache the underlying CGL context
    _render_context_cgl = [_render_context CGLContextObj];
    assert(_render_context_cgl);
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"render context: %p", _render_context_cgl);
    
    // make the rendering context current
    [_render_context makeCurrentContext];
    
    // initialize GLEW
    glewInit();
    
    // create the state object for the rendering context and store it in the context's client context slot
    NSObject<RXOpenGLStateProtocol>* state = [[RXOpenGLState alloc] initWithContext:_render_context_cgl];
    cgl_err = CGLSetParameter(_render_context_cgl, kCGLCPClientStorage, (const GLint*)&state);
    if (cgl_err != kCGLNoError) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLSetParameter for kCGLCPClientStorage failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
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
    
    // create the state object for the loading context and store it in the context's client context slot
    state = [[RXOpenGLState alloc] initWithContext:_load_context_cgl];
    cgl_err = CGLSetParameter(_load_context_cgl, kCGLCPClientStorage, (const GLint*)&state);
    if (cgl_err != kCGLNoError) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLSetParameter for kCGLCPClientStorage failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
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
    
    // disable the MT engine as it is a significant performance hit for Riven X; note that we ignore kCGLBadEnumeration errors because of Tiger
    cgl_err = CGLDisable(_render_context_cgl, kCGLCEMPEngine);
    if (cgl_err != kCGLNoError && cgl_err != kCGLBadEnumeration) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLEnable for kCGLCEMPEngine failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    cgl_err = CGLDisable(_load_context_cgl, kCGLCEMPEngine);
    if (cgl_err != kCGLNoError && cgl_err != kCGLBadEnumeration) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLEnable for kCGLCEMPEngine failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    // configure the view's autoresizing behavior to resize itself to match its container
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    // do base state setup
    [self _baseOpenGLStateSetup:_load_context_cgl];
    [self _baseOpenGLStateSetup:_render_context_cgl];
    
    // create the CV display link
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, &rx_render_output_callback, self);
    
    // working color space
    if ([GTMSystemVersion isLeopardOrGreater])
        _workingColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
    else
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
    
    if (_accelerator_service)
        IOObjectRelease(_accelerator_service);
    
    [_load_context release];
    
    CGColorSpaceRelease(_workingColorSpace);
    CGColorSpaceRelease(_displayColorSpace);
    
    [_cursor release];
    [_gl_extensions release];
    
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
    if ([w respondsToSelector:@selector(setPreferredBackingLocation:)])
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
    
    // on Tiger, we need to manually send a reshape notification now
    if ([GTMSystemVersion isTiger])
        [self reshape];
    
    // cache the imp for world render methods
    _renderTarget = [g_world stateCompositor];
    _renderDispatch = RXGetRenderImplementation([_renderTarget class], RXRenderingRenderSelector);
    _postFlushTasksDispatch = RXGetPostFlushTasksImplementation([_renderTarget class], RXRenderingPostFlushTasksSelector);
    
    // start the CV display link
    CVDisplayLinkStart(_displayLink);
}

extern CGError CGSAcceleratorForDisplayNumber(CGDirectDisplayID display, io_service_t* accelerator, uint32_t* index);

- (void)_updateAcceleratorService {
    CGLError cglerr;
    CGError cgerr;
    
    if (_accelerator_service) {
        IOObjectRelease(_accelerator_service);
        _accelerator_service = 0;
    }
    
    // get the display mask for the current virtual screen
    CGOpenGLDisplayMask display_mask;
    cglerr = CGLDescribePixelFormat(_cglPixelFormat, [_render_context currentVirtualScreen], kCGLPFADisplayMask, (GLint*)&display_mask);
    if (cglerr != kCGLNoError)
        return;
    
    // get the corresponding CG display ID
    CGDirectDisplayID display_id = CGOpenGLDisplayMaskToDisplayID(display_mask);
    if (display_id == kCGNullDirectDisplay)
        return;
    
    // use a private CG function to get the accelerator for that display ID
    uint32_t accelerator_index;
    cgerr = CGSAcceleratorForDisplayNumber(display_id, &_accelerator_service, &accelerator_index);
    if (cgerr != kCGErrorSuccess)
        return;
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
    
    [self _updateAcceleratorService];
    [self _updateTotalVRAM];
    
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"now using virtual screen %d driven by the \"%@\" renderer; VRAM: %ld MB total, %.2f MB free",
        [_render_context currentVirtualScreen], [RXWorldView rendererNameForID:renderer], _total_vram / 1024 / 1024, [self currentFreeVRAM:NULL] / 1024.0 / 1024.0);
    
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
    glRect.origin.x = ([self bounds].size.width - glRect.size.width) / 2.0;
    glRect.origin.y = ([self bounds].size.height - glRect.size.height) / 2.0;
    
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
    if (GLEW_APPLE_flush_buffer_range)
        glDisable(GL_MULTISAMPLE_ARB);
    
    // pixel store state
    [RXGetContextState(cgl_ctx) setUnpackClientStorage:GL_TRUE];
    
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
    if (GLEW_APPLE_flush_buffer_range)
        glHint(GL_TRANSFORM_HINT_APPLE, GL_NICEST);
    
    glReportError();
}

#pragma mark -
#pragma mark capabilities

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
        
        if (gluCheckExtension((const GLubyte*) "GL_ARB_shader_objects", extensions) &&
            gluCheckExtension((const GLubyte*) "GL_ARB_vertex_shader", extensions) &&
            gluCheckExtension((const GLubyte*) "GL_ARB_fragment_shader", extensions))
        {
            if (gluCheckExtension((const GLubyte*) "GL_ARB_shading_language_110", extensions)) {
                _glslMajorVersion = 1;
                _glslMinorVersion = 1;
            } else if (gluCheckExtension((const GLubyte*) "GL_ARB_shading_language_100", extensions)) {
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
    [_gl_extensions release];
    _gl_extensions = [[NSSet alloc] initWithArray:
                      [[NSString stringWithCString:(const char*)glGetString(GL_EXTENSIONS)
                                          encoding:NSASCIIStringEncoding] componentsSeparatedByString:@" "]];
    
    NSMutableString* features_message = [[NSMutableString alloc] initWithString:@"supported OpenGL features:\n"];
    if ([_gl_extensions containsObject:@"GL_ARB_texture_rectangle"])
        [features_message appendString:@"    texture rectangle (ARB)\n"];
    if ([_gl_extensions containsObject:@"GL_EXT_framebuffer_object"])
        [features_message appendString:@"    framebuffer objects (EXT)\n"];
    if ([_gl_extensions containsObject:@"GL_ARB_pixel_buffer_object"])
        [features_message appendString:@"    pixel buffer objects (ARB)\n"];
    if ([_gl_extensions containsObject:@"GL_APPLE_vertex_array_object"])
        [features_message appendString:@"    vertex array objects (APPLE)\n"];
    if ([_gl_extensions containsObject:@"GL_APPLE_flush_buffer_range"])
        [features_message appendString:@"    flush buffer range (APPLE)\n"];
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"%@", features_message);
    [features_message release];
}

- (void)_updateTotalVRAM {
    CGLError cglerr;
    
    // get the display mask for the current virtual screen
    CGOpenGLDisplayMask display_mask;
    cglerr = CGLDescribePixelFormat(_cglPixelFormat, [_render_context currentVirtualScreen], kCGLPFADisplayMask, (GLint*)&display_mask);
    if (cglerr != kCGLNoError) {
        _total_vram = -1;
        return;
    }
    
    // get the renderer ID for the current virtual screen
    GLint renderer;
    cglerr = CGLDescribePixelFormat(_cglPixelFormat, [_render_context currentVirtualScreen], kCGLPFARendererID, &renderer);
    if (cglerr != kCGLNoError) {
        _total_vram = -1;
        return;
    }
    
    // get the renderer info object for the display mask
    CGLRendererInfoObj renderer_info;
    GLint renderer_count;
    cglerr = CGLQueryRendererInfo(display_mask, &renderer_info, &renderer_count);
    if (cglerr != kCGLNoError) {
        _total_vram = -1;
        return;
    }
    
    // find the renderer index for the current renderer
    GLint renderer_index = 0;
    if (renderer_count > 1) {
        for (; renderer_index < renderer_count; renderer_index++) {
            GLint renderer_id;
            cglerr = CGLDescribeRenderer(renderer_info, 0, kCGLRPRendererID, &renderer_id);
            if (cglerr != kCGLNoError) {
                CGLDestroyRendererInfo(renderer_info);
                _total_vram = -1;
                return;
            }
            
            if ((renderer_id & kCGLRendererIDMatchingMask) == (renderer & kCGLRendererIDMatchingMask))
                break;
        }
    }
    
    if (renderer_index == renderer_count) {
        CGLDestroyRendererInfo(renderer_info);
        _total_vram = -1;
        return;
    }
    
    GLint total_vram = -1;
    cglerr = CGLDescribeRenderer(renderer_info, renderer_index, kCGLRPVideoMemory, &total_vram);
    if (cglerr != kCGLNoError) {
        _total_vram = -1;
        return;
    }
    CGLDestroyRendererInfo(renderer_info);
    
    _total_vram = total_vram;
}

- (ssize_t)currentFreeVRAM:(NSError**)error {        
    if (!_accelerator_service)
        ReturnValueWithError(-1, RXErrorDomain, kRXErrNoAcceleratorService, nil, error);
    
    // get the performance statistics ditionary out of the accelerator service
    CFDictionaryRef perf_stats = IORegistryEntryCreateCFProperty(_accelerator_service, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
    if (!perf_stats)
        ReturnValueWithError(-1, RXErrorDomain, kRXErrFailedToGetAcceleratorPerfStats, nil, error);
    
    // look for a number of keys (this is mostly reverse engineering and best-guess effort)
    CFNumberRef free_vram_number = NULL;
    ssize_t free_vram;
    BOOL free_number = NO;
    
//    free_vram_number = CFDictionaryGetValue(perf_stats, CFSTR("vramLargestFreeBytes"));
//    if (!free_vram_number) {
        free_vram_number = CFDictionaryGetValue(perf_stats, CFSTR("vramFreeBytes"));
        if (!free_vram_number) {
            free_vram_number = CFDictionaryGetValue(perf_stats, CFSTR("vramUsedBytes"));
            if (free_vram_number) {
                CFNumberGetValue(free_vram_number, kCFNumberLongType, &free_vram);
                free_vram_number = NULL;
                
                if (_total_vram != -1) {
                    free_vram = _total_vram - free_vram;
                    free_vram_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &free_vram);
                    free_number = YES;
                }
            }
        }
//    }
    
    // if we did not find or compute a free VRAM number, return an error
    if (!free_vram_number) {
        CFRelease(perf_stats);
        ReturnValueWithError(-1, RXErrorDomain, kRXErrFailedToFindFreeVRAMInformation, nil, error);
    }
    
    // get its value out
    CFNumberGetValue(free_vram_number, kCFNumberLongType, &free_vram);
    if (free_number)
        CFRelease(free_vram_number);
    
    // we're done with the perf stats
    CFRelease(perf_stats);
    
    return free_vram;
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
