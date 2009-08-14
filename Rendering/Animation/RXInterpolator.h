//
//  RXInterpolator.h
//  rivenx
//
//  Created by Jean-Francois Roy on 12/08/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "Rendering/Animation/RXAnimation.h"


@interface RXInterpolator : NSObject {
@public
    RXAnimation* animation;
}

- (id)initWithAnimation:(RXAnimation*)a;

- (float)value;

@end

@interface RXLinearInterpolator : RXInterpolator {
@public
    float start;
    float end;
}

- (id)initWithAnimation:(RXAnimation*)a start:(float)p0 end:(float)p1;

@end
