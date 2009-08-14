//
//  RXAnimation.m
//  rivenx
//
//  Created by Jean-François Roy on 11/04/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import "Rendering/Animation/RXAnimation.h"


static const double kDurationEpsilon = 0.000001;

@implementation RXAnimation

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithDuration:(double)d curve:(RXAnimationCurve)c {
    self = [super init];
    if (!self)
        return nil;
    
    duration = d;
    if (duration < kDurationEpsilon)
        duration = kDurationEpsilon;
    curve = c;
    
    [self start];
    
    return self;
}

- (void)start {
    start_time = RXTimingNow();
    done = NO;
}

- (float)progress {
    if (done)
        return 1.0f;
    float t = MAX(0.0, MIN(1.0, RXTimingTimestampDelta(RXTimingNow(), start_time) / duration));
    if (t >= 1.0f)
        done = YES;
    return t;
}

- (float)value {
    return [self applyCurve:[self progress]];
}

- (float)applyCurve:(float)t {
    switch (curve) {
        case RXAnimationCurveSquareSine:
        {
            double sine = sin(M_PI_2 * t);
            return sine * sine;
        }
        case RXAnimationCurveLinear:
        default:
            return t;
    }
}

@end
