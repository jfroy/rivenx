//
//  RXPicture.m
//  rivenx
//
//  Created by Jean-Francois Roy on 10/12/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "RXPicture.h"


@implementation RXPicture

+ (BOOL)accessInstanceVariablesDirectly {
	return NO;
}

- (id)init {
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (id)initWithTexture:(GLuint)texid vao:(GLuint)vao index:(GLuint)index owner:(id)owner {
	self = [super init];
	if (!self)
		return nil;
	
	_owner = owner;
	_tex = texid;
	_vao = vao;
	_index = index;
	
	return self;
}

- (id)owner {
	return _owner;
}

- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx framebuffer:(GLuint)fbo {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	
	// alias the render context state object pointer
	NSObject<RXOpenGLStateProtocol>* gl_state = g_renderContextState;
	// bind the picture's VAO
	[gl_state bindVertexArrayObject:_vao];
	
	// bind the picture's texture to TEXTURE_RECTANGLE_ARB
	glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _tex); glReportError();
	
	// draw the picture using a tri-strip
	glDrawArrays(GL_TRIANGLE_STRIP, _index, 4); glReportError();
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD	
}

@end
