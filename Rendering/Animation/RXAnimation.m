//
//  RXAnimation.m
//  rivenx
//
//  Created by Jean-François Roy on 11/04/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import "RXAnimation.h"

#import "RXWorldProtocol.h"


@implementation RXAnimation

- (id)initWithDuration:(NSTimeInterval)duration animationCurve:(NSAnimationCurve)animationCurve {
    self = [super initWithDuration:duration animationCurve:animationCurve];
    if (!self) return nil;
    
    // RXAnimation always runs on the animation thread in a non-blocking manner (but without creating its own thread)
    [self setAnimationBlockingMode:NSAnimationNonblocking];
    
    return self;
}

- (void)setAnimationBlockingMode:(NSAnimationBlockingMode)animationBlockingMode {
    // ignore animation blocking mode requests
}

- (void)startAnimation {
    if ([NSThread currentThread] != [g_world animationThread]) {
        [self performSelector:_cmd inThread:[g_world animationThread] waitUntilDone:NO];
        return;
    }
    
    [super startAnimation];
}

- (void)stopAnimation {
    if ([NSThread currentThread] != [g_world animationThread]) {
        [self performSelector:_cmd inThread:[g_world animationThread] waitUntilDone:NO];
        return;
    }
    
    [super stopAnimation];
}

@end
