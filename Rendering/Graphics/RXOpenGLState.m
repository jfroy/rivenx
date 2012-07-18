//
//  RXOpenGLState.m
//  rivenx
//
//  Created by Jean-Francois Roy on 08/12/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "RXOpenGLState.h"


@implementation RXOpenGLState

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

- (GLuint)bindVertexArrayObject:(GLuint)vao_id {
    // WARNING: ASSUMES THE CALLER HAS LOCKED THE CONTEXT
    if (vao_id == _vao_binding)
        return _vao_binding;
    
    GLuint old = _vao_binding;
    _vao_binding = vao_id;
    glBindVertexArrayAPPLE(vao_id); glReportError();
    
    return old;
}

- (GLenum)setUnpackClientStorage:(GLenum)state {
    if (state == _unpack_client_storage)
        return _unpack_client_storage;
    
    GLenum old = _unpack_client_storage;
    _unpack_client_storage = state;
    glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, state); glReportError();
    
    return old;
}

@end
