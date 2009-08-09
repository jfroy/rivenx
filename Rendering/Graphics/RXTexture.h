//
//  RXTexture.h
//  rivenx
//
//  Created by Jean-Francois Roy on 08/08/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RXRendering.h"


@interface RXTexture : NSObject {
@public
    GLuint texture;
    GLenum target;
    rx_size_t size;
    
@protected
    BOOL _delete_when_done;
}

- (id)initWithID:(GLuint)texid target:(GLenum)t size:(rx_size_t)s deleteWhenDone:(BOOL)dwd;

- (void)bindWithContext:(CGLContextObj)cgl_ctx lock:(BOOL)lock;

@end
