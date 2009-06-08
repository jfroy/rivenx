//
//  RXState.m
//  rivenx
//
//  Created by Jean-Francois Roy on 11/12/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import "RXRenderState.h"


@implementation RXRenderState

- (id)init {
    self = [super init];
    if (!self) return nil;
    
    return self;
}

- (void)dealloc {
#if defined(DEBUG)
    RXOLog(@"deallocating");
#endif
    [super dealloc];
}

- (id)delegate {
    return _delegate;
}

- (void)setDelegate:(id)delegate {
    _delegate = delegate;
}

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

- (void)keyDown:(NSEvent *)theEvent {
    NSString* characters = [theEvent charactersIgnoringModifiers];
    unichar firstCharacter = [characters characterAtIndex:0];
    
#if defined(DEBUG)
    RXOLog(@"caught keyDown: 0x%x", firstCharacter);
#endif
}

#endif

@end
