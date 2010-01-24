//
//  RXState.m
//  rivenx
//
//  Created by Jean-Francois Roy on 11/12/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import "RXRenderState.h"


@implementation RXRenderState

- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx framebuffer:(GLuint)fbo {
    // WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime {
    // WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
}

#pragma mark -

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)becomeFirstResponder {
    return YES;
}

- (BOOL)resignFirstResponder {
    return YES;
}

#if defined(DEBUG)

- (void)keyDown:(NSEvent*)event {
    RXOLog2(kRXLoggingEvents, kRXLoggingLevelDebug, @"caught keyDown: 0x%x", [[event charactersIgnoringModifiers] characterAtIndex:0]);
}

#endif

@end
