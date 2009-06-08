//
//  RXOpenGLState.m
//  rivenx
//
//  Created by Jean-Francois Roy on 08/12/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "RXOpenGLState.h"

#import <OpenGL/CGLMacro.h>


@implementation RXOpenGLState

+ (BOOL)accessInstanceVariablesDirectly {
    return NO;
}

- (void)_updateInternalState {
    glGetIntegerv(GL_VERTEX_ARRAY_BINDING_APPLE, (GLint*)&_vao_binding);
}

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithContext:(CGLContextObj)context {
    self = [super init];
    if (!self)
        return nil;
    
    cgl_ctx = context;
    
    return self;
}

- (void)dealloc {
    [super dealloc];
}

- (GLuint)currentVertexArrayObject {
    return _vao_binding;
}

- (void)bindVertexArrayObject:(GLuint)vao_id {
    // WARNING: ASSUMES THE CALLER HAS LOCKED THE CONTEXT
    if (vao_id != _vao_binding) {
        _vao_binding = vao_id;
        glBindVertexArrayAPPLE(vao_id); glReportError();
    }
}

@end
