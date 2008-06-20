/*
 *	RXRendering.h
 *	rivenx
 *
 *	Created by Jean-Francois Roy on 05/09/2005.
 *	Copyright 2005 MacStorm. All rights reserved.
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

__BEGIN_DECLS

struct _rx_point {
	GLint x;
	GLint y;
};
typedef struct _rx_point rx_point_t;

CF_INLINE rx_point_t RXPointMake(GLint x, GLint y) {
	rx_point_t point; point.x = x; point.y = y; return point;
}

struct _rx_size {
	GLsizei width;
	GLsizei height;
};
typedef struct _rx_size rx_size_t;

CF_INLINE rx_size_t RXSizeMake(GLsizei width, GLsizei height) {
	rx_size_t size; size.width = width; size.height = height; return size;
}

struct _rx_rect {
	rx_point_t origin;
	rx_size_t size;
};
typedef struct _rx_rect rx_rect_t;

CF_INLINE rx_rect_t RXRectMake(GLint x, GLint y, GLsizei width, GLsizei height) {
	rx_rect_t rect; rect.origin = RXPointMake(x, y); rect.size = RXSizeMake(width, height); return rect;
}

extern const rx_size_t kRXCardViewportSize;
extern const float kRXCardViewportBorderRatios[2]; // left, bottom

extern const double kRXTransitionDuration;

__END_DECLS

// world view protocol
@protocol RXWorldViewProtocol <NSCoding, NSObject>
- (NSWindow*)window;

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
@end

__BEGIN_DECLS

// the world view
extern NSObject<RXWorldViewProtocol>* g_worldView;

// convenience functions related to the world view
CF_INLINE rx_size_t RXGetGLViewportSize() {
	return [g_worldView viewportSize];
}

CF_INLINE id <RXWorldViewProtocol> RXGetWorldView() {
	return g_worldView;
}

__END_DECLS

// renderable object protocol
@protocol RXRenderingProtocol
- (CGRect)renderRect;
- (void)setRenderRect:(CGRect)rect;

- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx parent:(id)parent;
- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime parent:(id)parent;
@end

__BEGIN_DECLS

typedef void (*RXRendering_RenderIMP)(id, SEL, const CVTimeStamp*, CGLContextObj, id);
typedef void (*RXRendering_PerformPostFlushTasksIMP)(id, SEL, const CVTimeStamp*, id);

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

#define RXRenderingRenderSelector @selector(render:inContext:parent:)
#define RXRenderingPostFlushTasksSelector @selector(performPostFlushTasks:parent:)

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
