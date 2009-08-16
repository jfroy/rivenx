//
//  RXAnimation.h
//  rivenx
//
//  Created by Jean-François Roy on 11/04/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "Base/RXTiming.h"


@interface RXAnimation : NSObject {
    BOOL _done;
    
@public
    double duration;
    uint64_t start_time;
}

- (id)initWithDuration:(double)d;

- (void)start;

- (float)progress;

- (float)value;
- (float)valueAt:(float)t;

@end


enum {
    RXAnimationCurveLinear = 1,
    RXAnimationCurveSquareSine,
};
typedef uint32_t RXAnimationCurve;

@interface RXCannedAnimation : RXAnimation {
    RXAnimationCurve _curve;
}

- (id)initWithDuration:(double)d curve:(RXAnimationCurve)c;

@end


@interface RXCosineCurveAnimation : RXAnimation {
    float _omega;
}

- (id)initWithDuration:(double)d frequency:(float)f;

@end


@interface RXSineCurveAnimation : RXCosineCurveAnimation
@end
