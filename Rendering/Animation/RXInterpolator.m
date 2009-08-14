//
//  RXInterpolator.m
//  rivenx
//
//  Created by Jean-Francois Roy on 12/08/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import "RXInterpolator.h"


@implementation RXInterpolator

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithAnimation:(RXAnimation*)a {
    self = [super init];
    if (!self)
        return nil;
    
    animation = [a retain];
    return self;
}

- (void)dealloc {
    [animation release];
    [super dealloc];
}

- (float)value {
    return [animation value];
}

@end


@implementation RXLinearInterpolator

- (id)initWithAnimation:(RXAnimation*)a start:(float)p0 end:(float)p1 {
    self = [super initWithAnimation:a];
    if (!self)
        return nil;
    
    start = p0;
    end = p1;
    
    return self;
}

- (float)value {
    float t = [animation value];
    return (end * t) + ((1.0f - t) * start);
}

@end
