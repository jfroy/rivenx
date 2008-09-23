//
//	RXWorldView.h
//	rivenx
//
//	Created by Jean-Francois Roy on 04/09/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import "RXRendering.h"


@interface RXWorldView : NSOpenGLView <RXWorldViewProtocol> {
	BOOL _tornDown;
	
	NSOpenGLContext* _renderContext;
	NSOpenGLContext* _loadContext;
	
	CGLPixelFormatObj _cglPixelFormat;
	
	CGLContextObj _renderCGLContext;
	CGLContextObj _loadCGLContext;
	
	GLuint _glMajorVersion;
	GLuint _glMinorVersion;
	GLuint _glslMajorVersion;
	GLuint _glslMinorVersion;
	
	GLsizei _glWidth;
	GLsizei _glHeight;
	
	CGColorSpaceRef _workingColorSpace;
	CGColorSpaceRef _displayColorSpace;
	
	CVDisplayLinkRef _displayLink;
	
	float _menuBarHeight;
	
	id _renderTarget;
	rx_render_dispatch_t _renderDispatch;
	rx_post_flush_tasks_dispatch_t _postFlushTasksDispatch;
	
	BOOL _glInitialized;
	
	NSCursor* _cursor;
}

@end
