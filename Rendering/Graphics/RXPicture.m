//
//  RXPicture.m
//  rivenx
//
//  Created by Jean-Francois Roy on 10/12/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <OpenGL/CGLMacro.h>

#import "Rendering/Graphics/RXPicture.h"


@implementation RXPicture

+ (BOOL)accessInstanceVariablesDirectly {
    return NO;
}

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithTexture:(RXTexture*)texture vao:(GLuint)vao index:(GLuint)index owner:(id)owner {
    self = [super init];
    if (!self)
        return nil;
    
    _owner = owner;
    _texture = [texture retain];
    _vao = vao;
    _index = index;
    
    return self;
}

- (void)dealloc {
    [_texture release];
    [super dealloc];
}

- (id)owner {
    return _owner;
}

- (void)render:(const CVTimeStamp*)output_time inContext:(CGLContextObj)cgl_ctx framebuffer:(GLuint)fbo {
    // WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
    
    // alias the render context state object pointer
    NSObject<RXOpenGLStateProtocol>* gl_state = g_renderContextState;
    
    // bind the picture's VAO
    [gl_state bindVertexArrayObject:_vao];
    
    // bind the picture's texture
    [_texture bindWithContext:cgl_ctx lock:NO];
    
    // draw the picture using a tri-strip
    glDrawArrays(GL_TRIANGLE_STRIP, _index, 4); glReportError();
}

- (void)performPostFlushTasks:(const CVTimeStamp*)output_time {
    // WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD    
}

@end
