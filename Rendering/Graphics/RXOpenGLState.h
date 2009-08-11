//
//  RXOpenGLState.h
//  rivenx
//
//  Created by Jean-Francois Roy on 08/12/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "Rendering/RXRendering.h"


@interface RXOpenGLState : NSObject <RXOpenGLStateProtocol> {
    __weak CGLContextObj cgl_ctx;
    
    GLuint _vao_binding;
    GLint _unpack_client_storage;
}

- (id)initWithContext:(CGLContextObj)context;

@end
