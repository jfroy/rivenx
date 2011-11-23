//
//  RXInterpolator.h
//  rivenx
//
//  Created by Jean-Francois Roy on 12/08/2009.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"

#import "Rendering/Animation/RXAnimation.h"


@protocol RXInterpolator <NSObject>
- (RXAnimation*)animation;
- (float)value;
- (BOOL)isDone;
@end

@interface RXAnimationInterpolator : NSObject <RXInterpolator> {
    RXAnimation* _animation;
}

- (id)initWithAnimation:(RXAnimation*)a;

@end

@interface RXLinearInterpolator : RXAnimationInterpolator {
@public
    float start;
    float end;
}

- (id)initWithAnimation:(RXAnimation*)a start:(float)p0 end:(float)p1;

@end

@interface RXChainingInterpolator : NSObject <RXInterpolator> {
    NSMutableArray* _interpolators;
    id<RXInterpolator> _current;
}

- (void)addInterpolator:(id<RXInterpolator>)interpolator;

@end
