//
//  RXOpenGLState.h
//  rivenx
//
//  Created by Jean-Francois Roy on 08/12/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"

#import "Rendering/RXRendering.h"


@interface RXOpenGLState : NSObject <RXOpenGLStateProtocol> {
    CGLContextObj cgl_ctx;
    
    GLuint _vao_binding;
    GLenum _unpack_client_storage;
}

- (id)initWithContext:(CGLContextObj)context;

@end
