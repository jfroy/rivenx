//
//  RXWorldView.m
//  rivenx
//
//  Created by Jean-Francois Roy on 04/09/2005.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//


#import <OpenGL/CGLMacro.h>
#import <OpenGL/CGLRenderers.h>

#import "Rendering/Graphics/RXWorldView.h"

#import "Application/RXApplicationDelegate.h"
#import "Base/RXThreadUtilities.h"
#import "Engine/RXWorldProtocol.h"
#import "Utilities/GTMSystemVersion.h"

#import "Rendering/Graphics/GL/GLShaderProgramManager.h"

#ifndef kCGLRendererIDMatchingMask
#define kCGLRendererIDMatchingMask   0x00FE7F00
#endif


@interface RXWorldView (RXWorldView_Private)
+ (NSString*)rendererNameForID:(GLint)renderer;

- (void)_handleColorProfileChange:(NSNotification*)notification;

- (void)_initializeCardRendering;
- (void)_updateCardCoordinates;

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
    _renderContext = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
    if (!_renderContext) {
        // NSOpenGLPFARendererID, kCGLRendererGenericFloatID,
        
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"could not create the render OpenGL context");
        [self release];
        return nil;
    }
    
    // cache the underlying CGL pixel format
    _cglPixelFormat = [format CGLPixelFormatObj];
    
    // set the render context on the view and release it (e.g. transfer ownership to the view)
    [self setOpenGLContext:_renderContext];
    [_renderContext release];
    
    // cache the underlying CGL context
    _renderContextCGL = [_renderContext CGLContextObj];
    assert(_renderContextCGL);
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"render context: %p", _renderContextCGL);
    
    // make the rendering context current
    [_renderContext makeCurrentContext];
    
    // initialize GLEW
    glewInit();
    
    // create the state object for the rendering context and store it in the context's client context slot
    NSObject<RXOpenGLStateProtocol>* state = [[RXOpenGLState alloc] initWithContext:_renderContextCGL];
    cgl_err = CGLSetParameter(_renderContextCGL, kCGLCPClientStorage, (const GLint*)&state);
    if (cgl_err != kCGLNoError) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLSetParameter for kCGLCPClientStorage failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    // create a load context and pair it with the render context
    _loadContext = [[NSOpenGLContext alloc] initWithFormat:format shareContext:_renderContext];
    if (!_loadContext) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"could not create the resource load OpenGL context");
        [self release];
        return nil;
    }
    
    // cache the underlying CGL context
    _loadContextCGL = [_loadContext CGLContextObj];
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"load context: %p", _loadContextCGL);
    
    // create the state object for the loading context and store it in the context's client context slot
    state = [[RXOpenGLState alloc] initWithContext:_loadContextCGL];
    cgl_err = CGLSetParameter(_loadContextCGL, kCGLCPClientStorage, (const GLint*)&state);
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
    cgl_err = CGLSetParameter(_renderContextCGL, kCGLCPSwapInterval, &param);
    if (cgl_err != kCGLNoError) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLSetParameter for kCGLCPSwapInterval failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    // disable the MT engine as it is a significant performance hit for Riven X; note that we ignore kCGLBadEnumeration errors because of Tiger
    cgl_err = CGLDisable(_renderContextCGL, kCGLCEMPEngine);
    if (cgl_err != kCGLNoError && cgl_err != kCGLBadEnumeration) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLEnable for kCGLCEMPEngine failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    cgl_err = CGLDisable(_loadContextCGL, kCGLCEMPEngine);
    if (cgl_err != kCGLNoError && cgl_err != kCGLBadEnumeration) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLEnable for kCGLCEMPEngine failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    // do base state setup
    [self _baseOpenGLStateSetup:_loadContextCGL];
    [self _baseOpenGLStateSetup:_renderContextCGL];
    
    // initialize card rendering
    [self _initializeCardRendering];
    
    // create the CV display link
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, &rx_render_output_callback, self);
    
    // working color space
    if ([GTMSystemVersion isLeopardOrGreater])
        _workingColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
    else
        _workingColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    
    // sRGB color space
    _sRGBColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    
    // get the default cursor from the world
    _cursor = [[g_world defaultCursor] retain];
    
    // configure the view's autoresizing behavior to resize itself to match its container
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
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
    
    if (_acceleratorService)
        IOObjectRelease(_acceleratorService);
    
    [_loadContext release];
    
    CGColorSpaceRelease(_workingColorSpace);
    CGColorSpaceRelease(_displayColorSpace);
    CGColorSpaceRelease(_sRGBColorSpace);
    
    [_cursor release];
    [_gl_extensions release];
    
    [_scaleFilter release];
    [_ciContext release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark world view protocol

- (CGLContextObj)renderContext {
    return _renderContextCGL;
}

- (CGLContextObj)loadContext {
    return _loadContextCGL;
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

- (void)setCardRenderer:(id)renderer {
    _cardRenderer = RXGetRenderer(renderer);
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

- (void)mouseDown:(NSEvent*)theEvent {
    [[g_world cardRenderer] mouseDown:theEvent];
}

- (void)mouseUp:(NSEvent*)theEvent {
    [[g_world cardRenderer] mouseUp:theEvent];
}

- (void)mouseMoved:(NSEvent*)theEvent {
    [[g_world cardRenderer] mouseMoved:theEvent];
}

- (void)mouseDragged:(NSEvent*)theEvent {
    [[g_world cardRenderer] mouseDragged:theEvent];
}

- (void)keyDown:(NSEvent*)theEvent {
    [[g_world cardRenderer] keyDown:theEvent];
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
    
    CGLLockContext(_renderContextCGL);
    
    // re-create the CoreImage context with the new output color space
    NSDictionary* options = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)_workingColorSpace, kCIContextWorkingColorSpace,
        (id)_displayColorSpace, kCIContextOutputColorSpace,
        nil];
    [_ciContext release];
    _ciContext = [[CIContext contextWithCGLContext:_renderContextCGL pixelFormat:_cglPixelFormat options:options] retain];
    assert(_ciContext);
    
    CGLUnlockContext(_renderContextCGL);
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
    
    // start the CV display link
    CVDisplayLinkStart(_displayLink);
}

extern CGError CGSAcceleratorForDisplayNumber(CGDirectDisplayID display, io_service_t* accelerator, uint32_t* index);

- (void)_updateAcceleratorService {
    CGLError cglerr;
    CGError cgerr;
    
    if (_acceleratorService) {
        IOObjectRelease(_acceleratorService);
        _acceleratorService = 0;
    }
    
    // get the display mask for the current virtual screen
    CGOpenGLDisplayMask display_mask;
    cglerr = CGLDescribePixelFormat(_cglPixelFormat, [_renderContext currentVirtualScreen], kCGLPFADisplayMask, (GLint*)&display_mask);
    if (cglerr != kCGLNoError)
        return;
    
    // get the corresponding CG display ID
    CGDirectDisplayID display_id = CGOpenGLDisplayMaskToDisplayID(display_mask);
    if (display_id == kCGNullDirectDisplay)
        return;
    
    // use a private CG function to get the accelerator for that display ID
    uint32_t accelerator_index;
    cgerr = CGSAcceleratorForDisplayNumber(display_id, &_acceleratorService, &accelerator_index);
    if (cgerr != kCGErrorSuccess)
        return;
}

- (void)update {    
    [super update];
    
    // the virtual screen has changed, reconfigure the contexes and the display link
    
    CGLLockContext(_renderContextCGL);
    CGLLockContext(_loadContextCGL);
    
    if (_displayLink)
        CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, _renderContextCGL, _cglPixelFormat);
    [_loadContext setCurrentVirtualScreen:[_renderContext currentVirtualScreen]];
    
    GLint renderer;
    CGLDescribePixelFormat(_cglPixelFormat, [_renderContext currentVirtualScreen], kCGLPFARendererID, &renderer);
    
    [self _updateAcceleratorService];
    [self _updateTotalVRAM];
    
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"now using virtual screen %d driven by the \"%@\" renderer; VRAM: %ld MB total, %.2f MB free",
        [_renderContext currentVirtualScreen], [RXWorldView rendererNameForID:renderer], _totalVRAM / 1024 / 1024, [self currentFreeVRAM:NULL] / 1024.0 / 1024.0);
    
    // determine OpenGL version and features
    [self _determineGLVersion:_renderContextCGL];
    [self _determineGLFeatures:_renderContextCGL];
    
    // FIXME: determine if we need to fallback to software and do so here; this may not be required since we allow fallback in the pixel format
    
    CGLUnlockContext(_loadContextCGL);
    CGLUnlockContext(_renderContextCGL);
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
    CGLContextObj cgl_ctx = _renderContextCGL;
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
    
    // update the card coordinates
    [self _updateCardCoordinates];
    
    // update the scale filter
    if (!_scaleFilter) {
        _scaleFilter = [[CIFilter filterWithName:@"CILanczosScaleTransform"] retain];
        assert(_scaleFilter);
        [_scaleFilter setDefaults];
    }
    
    NSRect scale_rect = RXRenderScaleRect();
    [_scaleFilter setValue:[NSNumber numberWithFloat:scale_rect.size.width] forKey:kCIInputScaleKey];
    [_scaleFilter setValue:[NSNumber numberWithFloat:scale_rect.size.width / scale_rect.size.height] forKey:kCIInputAspectRatioKey];
    
    // let others know that the surface has changed size
#if defined(DEBUG)
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"sending RXOpenGLDidReshapeNotification notification");
#endif
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RXOpenGLDidReshapeNotification" object:self];
    
    CGLUnlockContext(cgl_ctx);
}

#pragma mark -
#pragma mark OpenGL initialization

- (void)_initializeCardRendering {
    CGLContextObj cgl_ctx = _renderContextCGL;
    NSObject<RXOpenGLStateProtocol>* gl_state = RXGetContextState(cgl_ctx);
    
    glGenFramebuffersEXT(1, &_cardFBO);
    glGenTextures(1, &_cardTexture);
    
    // bind the texture
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _cardTexture); glReportError();
    
    // texture parameters
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glReportError();
    
    // disable client storage because it's incompatible with allocating texture space with NULL (which is what we want to do for FBO color attachement textures)
    GLenum client_storage = [gl_state setUnpackClientStorage:GL_FALSE];
    
    // allocate memory for the texture
    glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, kRXCardViewportSize.width, kRXCardViewportSize.height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL); glReportError();
    
    // color0 texture attach
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _cardFBO); glReportError();
    glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_ARB, _cardTexture, 0); glReportError();
        
    // completeness check
    GLenum status = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
    if (status != GL_FRAMEBUFFER_COMPLETE_EXT) {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"card FBO not complete, status 0x%04x\n", (unsigned int)status);
    }
    
    // create the card VBO and VAO
    glGenVertexArraysAPPLE(1, &_cardVAO); glReportError();
    [gl_state bindVertexArrayObject:_cardVAO];
    
    glGenBuffers(1, &_cardVBO);
    glBindBuffer(GL_ARRAY_BUFFER, _cardVBO); glReportError();
    
    if (GLEW_APPLE_flush_buffer_range)
        glBufferParameteriAPPLE(GL_ARRAY_BUFFER, GL_BUFFER_FLUSHING_UNMAP_APPLE, GL_FALSE);
    glBufferData(GL_ARRAY_BUFFER, 16 * sizeof(GLfloat), NULL, GL_STATIC_DRAW); glReportError();
    
    // configure the VAs
    glEnableVertexAttribArray(RX_ATTRIB_POSITION); glReportError();
    glVertexAttribPointer(RX_ATTRIB_POSITION, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), NULL); glReportError();
    
    glEnableVertexAttribArray(RX_ATTRIB_TEXCOORD0); glReportError();
    glVertexAttribPointer(RX_ATTRIB_TEXCOORD0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), BUFFER_OFFSET(NULL, 2 * sizeof(GLfloat))); glReportError();
    
    _cardProgram = [[GLShaderProgramManager sharedManager]
                    standardProgramWithFragmentShaderName:@"card"
                    extraSources:nil
                    epilogueIndex:0
                    context:cgl_ctx
                    error:NULL];
    assert(_cardProgram);
    
    glUseProgram(_cardProgram); glReportError();
    
    GLint uniform_loc = glGetUniformLocation(_cardProgram, "destination_card"); glReportError();
    assert(uniform_loc != -1);
    glUniform1i(uniform_loc, 0); glReportError();
    
    uniform_loc = glGetUniformLocation(_cardProgram, "modulate_color"); glReportError();
    assert(uniform_loc != -1);
    glUniform4f(uniform_loc, 1.f, 1.f, 1.f, 1.f); glReportError();
    
    // restore state
    glUseProgram(0);
    [gl_state bindVertexArrayObject:0];
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
    [gl_state setUnpackClientStorage:client_storage];
    glReportError();
}

- (void)_updateCardCoordinates {
    CGLContextObj cgl_ctx = _renderContextCGL;
    NSObject<RXOpenGLStateProtocol>* gl_state = RXGetContextState(cgl_ctx);
    
    [gl_state bindVertexArrayObject:_cardVAO];
    
    struct _attribs {
        GLfloat pos[2];
        GLfloat tex[2];
    };
    assert(sizeof(struct _attribs) == 4 * sizeof(GLfloat));
    struct _attribs* attribs = (struct _attribs*)glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY); glReportError();
    assert(attribs);
    
    rx_rect_t contentRect = RXEffectiveRendererFrame();
    
    attribs[0].pos[0] = contentRect.origin.x;                               attribs[0].pos[1] = contentRect.origin.y;
    attribs[0].tex[0] = 0.0f;                                               attribs[0].tex[1] = 0.0f;
    
    attribs[1].pos[0] = contentRect.origin.x + contentRect.size.width;      attribs[1].pos[1] = contentRect.origin.y;
    attribs[1].tex[0] = (GLfloat)kRXCardViewportSize.width;                 attribs[1].tex[1] = 0.0f;
    
    attribs[2].pos[0] = contentRect.origin.x;                               attribs[2].pos[1] = contentRect.origin.y + contentRect.size.height;
    attribs[2].tex[0] = 0.0f;                                               attribs[2].tex[1] = (GLfloat)kRXCardViewportSize.height;
    
    attribs[3].pos[0] = contentRect.origin.x + contentRect.size.width;      attribs[3].pos[1] = contentRect.origin.y + contentRect.size.height;
    attribs[3].tex[0] = (GLfloat)kRXCardViewportSize.width;                 attribs[3].tex[1] = (GLfloat)kRXCardViewportSize.height;
    
    if (GLEW_APPLE_flush_buffer_range)
        glFlushMappedBufferRangeAPPLE(GL_ARRAY_BUFFER, 0, 16 * sizeof(GLfloat));
    glUnmapBuffer(GL_ARRAY_BUFFER);
    glReportError();
    
    [gl_state bindVertexArrayObject:0];
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
    cglerr = CGLDescribePixelFormat(_cglPixelFormat, [_renderContext currentVirtualScreen], kCGLPFADisplayMask, (GLint*)&display_mask);
    if (cglerr != kCGLNoError) {
        _totalVRAM = -1;
        return;
    }
    
    // get the renderer ID for the current virtual screen
    GLint renderer;
    cglerr = CGLDescribePixelFormat(_cglPixelFormat, [_renderContext currentVirtualScreen], kCGLPFARendererID, &renderer);
    if (cglerr != kCGLNoError) {
        _totalVRAM = -1;
        return;
    }
    
    // get the renderer info object for the display mask
    CGLRendererInfoObj renderer_info;
    GLint renderer_count;
    cglerr = CGLQueryRendererInfo(display_mask, &renderer_info, &renderer_count);
    if (cglerr != kCGLNoError) {
        _totalVRAM = -1;
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
                _totalVRAM = -1;
                return;
            }
            
            if ((renderer_id & kCGLRendererIDMatchingMask) == (renderer & kCGLRendererIDMatchingMask))
                break;
        }
    }
    
    if (renderer_index == renderer_count) {
        CGLDestroyRendererInfo(renderer_info);
        _totalVRAM = -1;
        return;
    }
    
    GLint total_vram = -1;
    cglerr = CGLDescribeRenderer(renderer_info, renderer_index, kCGLRPVideoMemory, &total_vram);
    if (cglerr != kCGLNoError) {
        _totalVRAM = -1;
        return;
    }
    CGLDestroyRendererInfo(renderer_info);
    
    _totalVRAM = total_vram;
}

- (ssize_t)currentFreeVRAM:(NSError**)error {        
    if (!_acceleratorService)
        ReturnValueWithError(-1, RXErrorDomain, kRXErrNoAcceleratorService, nil, error);
    
    // get the performance statistics ditionary out of the accelerator service
    CFDictionaryRef perf_stats = IORegistryEntryCreateCFProperty(_acceleratorService, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
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
                
                if (_totalVRAM != -1) {
                    free_vram = _totalVRAM - free_vram;
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

- (BOOL)isUsingCoreImage {
    return _useCoreImage;
}

- (void)setUseCoreImage:(BOOL)flag {
    _useCoreImage = flag;
}

- (void)_render:(const CVTimeStamp*)outputTime {
    if (_tornDown)
        return;
    
    CGLContextObj cgl_ctx = _renderContextCGL;
    CGLSetCurrentContext(cgl_ctx);
    CGLLockContext(cgl_ctx);
    
    NSObject<RXOpenGLStateProtocol>* gl_state = RXGetContextState(cgl_ctx);
    
    // clear to black
    glClear(GL_COLOR_BUFFER_BIT);
    
//    OSSpinLockLock(&_render_lock);
//    NSArray* renderStates = [_renderStates retain];
//    id<RXInterpolator> fade_interpolator = [_fade_interpolator retain];
//    NSInvocation* fade_callback = [_fade_animation_callback retain];
//    OSSpinLockUnlock(&_render_lock);
    
    if (_cardRenderer.target) {
        // bind the card FBO, clear the color buffer and call down to the card renderer
        glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _cardFBO); glReportError();
        glClear(GL_COLOR_BUFFER_BIT);
        _cardRenderer.render.imp(_cardRenderer.target, _cardRenderer.render.sel, outputTime, cgl_ctx, _cardFBO);
        
        // bind the window server FBO
        glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0); glReportError();
        
        if (_useCoreImage) {
            glUseProgram(0); glReportError();
            [gl_state bindVertexArrayObject:0];
            
            // scale the card texture
            CIImage* cardImage = [CIImage imageWithTexture:_cardTexture size:CGSizeMake(kRXCardViewportSize.width, kRXCardViewportSize.height) flipped:0 colorSpace:_sRGBColorSpace];
            [_scaleFilter setValue:cardImage forKey:kCIInputImageKey];
            CIImage* scaledCardImage = [_scaleFilter valueForKey:kCIOutputImageKey];
            
            // render the scaled card texture; note that we need to inset the image by one pixel to avoid garbage pixels output by the lanczos filter
            rx_rect_t contentRect = RXEffectiveRendererFrame();
            CGRect contentCGRect = CGRectMake(contentRect.origin.x, contentRect.origin.y, contentRect.size.width, contentRect.size.height);
            [_ciContext drawImage:scaledCardImage inRect:contentCGRect fromRect:CGRectInset([scaledCardImage extent], 1, 1)];
        } else {
            glUseProgram(_cardProgram); glReportError();
            [gl_state bindVertexArrayObject:_cardVAO];
            
            glActiveTexture(GL_TEXTURE0); glReportError();
            glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _cardTexture); glReportError();
            
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); glReportError();
            
            glUseProgram(0); glReportError();
            [gl_state bindVertexArrayObject:0];
        }
    
//#if defined(DEBUG_GL)
//    glValidateProgram(_compositing_program); glReportError();
//    GLint valid;
//    glGetProgramiv(_compositing_program, GL_VALIDATE_STATUS, &valid);
//    if (valid != GL_TRUE)
//        RXOLog(@"program not valid: %u", _compositing_program);
//#endif
//    
//    // if we have a fade animation, apply it's value to the blend weight 0 and call its completion callback if it's reached its end
//    if (fade_interpolator) {
//        _texture_blend_weights[0] = [fade_interpolator value];
//        if ([fade_interpolator isDone]) {
//            [fade_callback performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
//            
//            OSSpinLockLock(&_render_lock);
//            if (fade_interpolator == _fade_interpolator) {
//                [_fade_interpolator release];
//                _fade_interpolator = nil;
//            }
//            if (fade_callback == _fade_animation_callback) {
//                [_fade_animation_callback release];
//                _fade_animation_callback = nil;
//            }
//            OSSpinLockUnlock(&_render_lock);
//        }
//    }
//    
//    // bind the compositor program and update the render state blend uniform
//    glUseProgram(_compositing_program); glReportError();
//    glUniform4fv(_texture_blend_weights_uniform, 1, _texture_blend_weights); glReportError();
//    
//    // bind the compositing vao
//    [gl_state bindVertexArrayObject:_compositing_vao];
//    
//    // bind render state textures
//    uint32_t state_count = [_states count];
//    for (uint32_t state_i = 0; state_i < state_count; state_i++) {
//        glActiveTexture(GL_TEXTURE0 + state_i); glReportError();
//        GLuint texture = ((RXRenderStateCompositionDescriptor*)[_states objectAtIndex:state_i])->texture;
//        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, texture); glReportError();
//    }
//    
//    // render all states at once!
//    glDrawArrays(GL_QUADS, 0, 4); glReportError();
//    
//    // set the active texture unit to TEXTURE0 (Riven X assumption)
//    glActiveTexture(GL_TEXTURE0); glReportError();
//    
//    // bind program 0 (FF processing)
//    glUseProgram(0); glReportError();
    
        // call down to the card renderer again, this time to perform rendering into the system framebuffer
        _cardRenderer.renderInMainRT.imp(_cardRenderer.target, _cardRenderer.render.sel, cgl_ctx);
    }
    
//    [fade_callback release];
//    [fade_interpolator release];
//    [renderStates release];
    
    // glFlush and swap the front and back buffers
    CGLFlushDrawable(cgl_ctx);
    
    // finally call down to the card renderer one last time to let it take post-flush actions
    if (_cardRenderer.target)
        _cardRenderer.flush.imp(_cardRenderer.target, _cardRenderer.flush.sel, outputTime);
    
    CGLUnlockContext(cgl_ctx);
}

- (void)drawRect:(NSRect)rect {

}

@end
