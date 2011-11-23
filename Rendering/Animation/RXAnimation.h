//
//  RXAnimation.h
//  rivenx
//
//  Created by Jean-François Roy on 11/04/2007.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"
#import "Base/RXTiming.h"


@interface RXAnimation : NSObject {
    uint64_t _start_time;

@public
    double duration;
    BOOL done;
}

- (id)initWithDuration:(double)d;

- (void)startNow;
- (void)startAt:(uint64_t)timestamp;
- (uint64_t)startTimestamp;
- (double)timeLeft;

- (float)progress;
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
