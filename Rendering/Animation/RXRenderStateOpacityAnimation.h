//
//  RXRenderStateOpacityAnimation.h
//  rivenx
//
//  Created by Jean-Francois Roy on 2008-06-20.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "RXAnimation.h"
#import "RXStateCompositor.h"


@interface RXRenderStateOpacityAnimation : RXAnimation {
    RXStateCompositor* _compositor;
    RXRenderState* _state;
    
    GLfloat _start;
    GLfloat _end;
    BOOL inverse;
}

- (id)initWithState:(RXRenderState*)state targetOpacity:(GLfloat)opacity duration:(NSTimeInterval)duration;

@end
