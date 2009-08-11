/*
 *  RXRendering.h
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 05/09/2005.
 *  Copyright 2005 MacStorm. All rights reserved.
 *
 */

#if !defined(__OBJC__)
#error RXRendering.h requires Objective-C
#else

#import <sys/cdefs.h>

#import "Graphics/GL/GL.h"
#import <OpenGL/CGLMacro.h>
#import "Graphics/GL/GL_debug.h"

#import <Cocoa/Cocoa.h>
#import <QuartzCore/CoreVideo.h>

#import "Engine/RXCoreStructures.h"

__BEGIN_DECLS

struct rx_point {
    GLint x;
    GLint y;
};
typedef struct rx_point rx_point_t;

CF_INLINE rx_point_t RXPointMake(GLint x, GLint y) {
    rx_point_t point; point.x = x; point.y = y; return point;
}

struct rx_size {
    GLsizei width;
    GLsizei height;
};
typedef struct rx_size rx_size_t;

CF_INLINE rx_size_t RXSizeMake(GLsizei width, GLsizei height) {
    rx_size_t size; size.width = width; size.height = height; return size;
}

struct rx_rect {
    rx_point_t origin;
    rx_size_t size;
};
typedef struct rx_rect rx_rect_t;

CF_INLINE rx_rect_t RXRectMake(GLint x, GLint y, GLsizei width, GLsizei height) {
    rx_rect_t rect; rect.origin = RXPointMake(x, y); rect.size = RXSizeMake(width, height); return rect;
}

struct rx_event {
    NSPoint location;
    NSTimeInterval timestamp;
};
typedef struct rx_event rx_event_t;

struct rx_card_sfxe {
    struct rx_sfxe_record* record;
    uint32_t* offsets;
};
typedef struct rx_card_sfxe rx_card_sfxe;

#pragma mark -
#pragma mark rendering constants

extern const rx_size_t kRXRendererViewportSize;

extern const rx_size_t kRXCardViewportSize;
extern const rx_point_t kRXCardViewportOriginOffset;

extern const double kRXTransitionDuration;

extern const float kRXSoundGainDivisor;

#define RX_ATTRIB_POSITION 0
#define RX_ATTRIB_TEXCOORD0 1

#pragma mark -

__END_DECLS

@protocol RXOpenGLStateProtocol
- (GLuint)bindVertexArrayObject:(GLuint)vao_id;
- (GLenum)setUnpackClientStorage:(GLenum)state;
@end

@protocol RXWorldViewProtocol <NSCoding>
- (void)tearDown;

- (CGLContextObj)renderContext;
- (CGLContextObj)loadContext;

- (CGLPixelFormatObj)cglPixelFormat;
- (CVDisplayLinkRef)displayLink;

- (CGColorSpaceRef)workingColorSpace;
- (CGColorSpaceRef)displayColorSpace;

- (rx_size_t)viewportSize;

- (NSCursor*)cursor;
- (void)setCursor:(NSCursor*)cursor;

- (ssize_t)currentFreeVRAM:(NSError**)error;
@end

__BEGIN_DECLS

#pragma mark -
#pragma mark rendering globals

// the world view
extern NSView<RXWorldViewProtocol>* g_worldView;

#pragma mark -

CF_INLINE NSObject<RXOpenGLStateProtocol>* RXGetContextState(CGLContextObj cgl_ctx) {
    NSObject<RXOpenGLStateProtocol>* state = nil;
    CGLGetParameter(cgl_ctx, kCGLCPClientStorage, (GLint*)&state);
    return state;
}

CF_INLINE rx_size_t RXGetGLViewportSize() {
    return [g_worldView viewportSize];
}

CF_INLINE rx_rect_t RXEffectiveRendererFrame() {
    // FIXME: need to cache the result of this function, since it should not change too often
    rx_size_t viewportSize = RXGetGLViewportSize();
    rx_size_t contentSize = kRXRendererViewportSize;
    
//    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"FullScreenMode"] && [[NSUserDefaults standardUserDefaults] boolForKey:@"StretchToFit"]) {
//        float viewportAR = (float)viewportSize.width / (float)viewportSize.height;
//        float contentAR = (float)contentSize.width / (float)contentSize.height;
//        
//        if (viewportAR > 0) {
//            contentSize.height = viewportSize.height;
//            contentSize.width = contentSize.height * contentAR;
//        } else {
//            contentSize.width = viewportSize.width;
//            contentSize.height = viewportSize.width / contentAR;
//        }
//    }
    
    return RXRectMake((viewportSize.width / 2) - (contentSize.width / 2), (viewportSize.height / 2) - (contentSize.height / 2), contentSize.width, contentSize.height);
}

CF_INLINE NSRect RXRenderScaleRect() {
    rx_rect_t render_frame = RXEffectiveRendererFrame();
    float scale_x = (float)render_frame.size.width / (float)kRXRendererViewportSize.width;
    float scale_y = (float)render_frame.size.height / (float)kRXRendererViewportSize.height;
    return NSMakeRect(render_frame.origin.x, render_frame.origin.y, scale_x, scale_y);
}

#pragma mark -

CF_INLINE NSPoint RXMakeNSPointFromPoint(uint16_t x, uint16_t y) {
    return NSMakePoint((float)x, (float)y);
}

CF_INLINE NSRect RXMakeCompositeDisplayRect(uint16_t left, uint16_t top, uint16_t right, uint16_t bottom) {
    return NSMakeRect((float)left, (float)(kRXCardViewportSize.height - bottom), (float)(right - left), (float)(bottom - top));
}

CF_INLINE NSRect RXMakeCompositeDisplayRectFromCoreRect(rx_core_rect_t rect) {
    return NSMakeRect((float)rect.left, (float)(kRXCardViewportSize.height - rect.bottom), (float)(rect.right - rect.left), (float)(rect.bottom - rect.top));
}

CF_INLINE rx_core_rect_t RXMakeCoreRectFromCompositeDisplayRect(NSRect rect) {
    rx_core_rect_t r;
    r.left = rect.origin.x;
    r.right = rect.origin.x + rect.size.width;
    r.bottom = kRXCardViewportSize.height - rect.origin.y;
    r.top = r.bottom - rect.size.height;
    return r;
}

CF_INLINE NSRect RXTransformRectCoreToWorld(rx_core_rect_t rect) {
    NSRect scale_rect = RXRenderScaleRect();
    NSRect composite_rect = RXMakeCompositeDisplayRectFromCoreRect(rect);
        
    NSRect world_rect;
    world_rect.origin.x = scale_rect.origin.x + (composite_rect.origin.x + kRXCardViewportOriginOffset.x) * scale_rect.size.width;
    world_rect.origin.y = scale_rect.origin.y + (composite_rect.origin.y + kRXCardViewportOriginOffset.y) * scale_rect.size.height;
    world_rect.size.width = composite_rect.size.width * scale_rect.size.width;
    world_rect.size.height = composite_rect.size.height * scale_rect.size.height;
    return world_rect;
}

CF_INLINE rx_core_rect_t RXTransformRectWorldToCore(NSRect rect) {
    NSRect scale_rect = RXRenderScaleRect();
    
    // if the rect's size is <inf, inf>, rect is likely a mouse vector, so clamp to 0
    if (isinf(rect.size.width) && isinf(rect.size.height)) {
        rect.size.width = 0.0f;
        rect.size.height = 0.0f;
    }
    
    NSRect composite_rect;
    composite_rect.origin.x = ((rect.origin.x - scale_rect.origin.x) / scale_rect.size.width) - kRXCardViewportOriginOffset.x;
    composite_rect.origin.y = ((rect.origin.y - scale_rect.origin.y) / scale_rect.size.height) - kRXCardViewportOriginOffset.y;
    composite_rect.size.width = rect.size.width / scale_rect.size.width;
    composite_rect.size.height = rect.size.height / scale_rect.size.height;
    return RXMakeCoreRectFromCompositeDisplayRect(composite_rect);
}

#pragma mark -

__END_DECLS

// renderable object protocol
@protocol RXRenderingProtocol
- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx framebuffer:(GLuint)fbo;
- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime;
@end

__BEGIN_DECLS

typedef void (*RXRendering_RenderIMP)(id, SEL, const CVTimeStamp*, CGLContextObj, GLuint);
typedef void (*RXRendering_PerformPostFlushTasksIMP)(id, SEL, const CVTimeStamp*);

struct _rx_render_dispatch {
    RXRendering_RenderIMP imp;
    SEL sel;
};
typedef struct _rx_render_dispatch rx_render_dispatch_t;

struct _rx_post_flush_tasks_dispatch {
    RXRendering_PerformPostFlushTasksIMP imp;
    SEL sel;
};
typedef struct _rx_post_flush_tasks_dispatch rx_post_flush_tasks_dispatch_t;

#define RXRenderingRenderSelector @selector(render:inContext:framebuffer:)
#define RXRenderingPostFlushTasksSelector @selector(performPostFlushTasks:)

CF_INLINE rx_render_dispatch_t RXGetRenderImplementation(Class impClass, SEL sel) {
    rx_render_dispatch_t d;
    d.sel = sel;
    d.imp = (RXRendering_RenderIMP)[impClass instanceMethodForSelector:sel];
    return d;
}

CF_INLINE rx_post_flush_tasks_dispatch_t RXGetPostFlushTasksImplementation(Class impClass, SEL sel) {
    rx_post_flush_tasks_dispatch_t d;
    d.sel = sel;
    d.imp = (RXRendering_PerformPostFlushTasksIMP)[impClass instanceMethodForSelector:sel];
    return d;
}

__END_DECLS

#endif // __OBJC__
