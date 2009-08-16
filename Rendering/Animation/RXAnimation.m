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

- (id)initWithDuration:(double)d {
    self = [super init];
    if (!self)
        return nil;
    
    duration = d;
    if (duration < kDurationEpsilon)
        duration = kDurationEpsilon;
    
    [self start];
    
    return self;
}

- (id)copyWithZone:(NSZone*)zone {
    RXAnimation* copy = [[[self class] allocWithZone:zone] initWithDuration:duration];
    copy->start_time = start_time;
    return copy;
}

- (void)start {
    start_time = RXTimingNow();
    _done = NO;
}

- (float)progress {
    if (_done)
        return 1.0f;
    float t = MAX(0.0, MIN(1.0, RXTimingTimestampDelta(RXTimingNow(), start_time) / duration));
    if (t >= 1.0f)
        _done = YES;
    return t;
}

- (float)value {
    return [self valueAt:[self progress]];
}

- (float)valueAt:(float)t {
    return t;
}

@end


@implementation RXCannedAnimation

- (id)initWithDuration:(double)d {
    return [self initWithDuration:d curve:RXAnimationCurveLinear];
}

- (id)initWithDuration:(double)d curve:(RXAnimationCurve)c {
    self = [super initWithDuration:d];
    if (!self)
        return nil;
    
    _curve = c;
    
    return self;
}

- (id)copyWithZone:(NSZone*)zone {
    RXCannedAnimation* copy = [super copyWithZone:zone];
    copy->_curve = _curve;
    return copy;
}

- (float)valueAt:(float)t {
    switch (_curve) {
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


@implementation RXCosineCurveAnimation

- (id)initWithDuration:(double)d {
    return [self initWithDuration:d frequency:1.0f];
}

- (id)initWithDuration:(double)d frequency:(float)f {
    self = [super initWithDuration:d];
    if (!self)
        return nil;
    
    _omega = f * 2.0f * M_PI;
    
    return self;
}

- (id)copyWithZone:(NSZone*)zone {
    RXCannedAnimation* copy = [super copyWithZone:zone];
    copy->_omega = _omega;
    return copy;
}

- (float)valueAt:(float)t {
    return 0.5f * cosf(_omega * t) + 0.5f;
}

@end


@implementation RXSineCurveAnimation

- (float)valueAt:(float)t {
    return -0.5f * cosf(_omega * t) + 0.5f;
}

@end
