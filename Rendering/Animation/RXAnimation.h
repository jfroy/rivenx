//
//  RXAnimation.h
//  rivenx
//
//  Created by Jean-François Roy on 11/04/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "Base/RXTiming.h"


enum {
    RXAnimationCurveLinear = 1,
    RXAnimationCurveSquareSine,
};
typedef uint32_t RXAnimationCurve;

@interface RXAnimation : NSObject {
@public
    double duration;
    uint64_t start_time;
    RXAnimationCurve curve;
}

- (id)initWithDuration:(double)d curve:(RXAnimationCurve)c;

- (void)start;

- (float)progress;

- (float)value;
- (float)applyCurve:(float)t;

@end
