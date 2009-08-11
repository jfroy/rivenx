//
//  RXTexture.m
//  rivenx
//
//  Created by Jean-Francois Roy on 08/08/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import "RXTexture.h"


@implementation RXTexture

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithID:(GLuint)texid target:(GLenum)t size:(rx_size_t)s deleteWhenDone:(BOOL)dwd {
    self = [super init];
    if (!self)
        return nil;
    
    texture = texid;
    target = t;
    size = s;
    
    _delete_when_done = dwd;
    
    return self;
}

- (NSString*)description {
    return [NSString stringWithFormat: @"%@ {texture=%u, delete_when_done=%d}", [super description], texture, _delete_when_done];
}

- (void)dealloc {
#if defined(DEBUG)
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"deallocating");
#endif

    if (_delete_when_done) {
        CGLContextObj cgl_ctx = [g_worldView loadContext];
        CGLLockContext(cgl_ctx);
        glDeleteTextures(1, &texture);
        CGLUnlockContext(cgl_ctx);
    }
    
    [super dealloc];
}

- (void)bindWithContext:(CGLContextObj)cgl_ctx lock:(BOOL)lock {
    if (lock)
        CGLLockContext(cgl_ctx);
    glBindTexture(target, texture); glReportError();
    if (lock)
        CGLUnlockContext(cgl_ctx);
}

@end
