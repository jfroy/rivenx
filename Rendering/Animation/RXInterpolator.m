//
//  RXInterpolator.m
//  rivenx
//
//  Created by Jean-Francois Roy on 12/08/2009.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "RXInterpolator.h"


@implementation RXAnimationInterpolator

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithAnimation:(RXAnimation*)a {
    self = [super init];
    if (!self)
        return nil;
    
    _animation = [a retain];
    
    return self;
}

- (void)dealloc {
    [_animation release];
    [super dealloc];
}

- (RXAnimation*)animation {
    return [[_animation retain] autorelease];
}

- (float)value {
    return [_animation valueAt:[_animation progress]];
}

- (BOOL)isDone {
    [_animation progress];
    return _animation->done;
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
    float t = [_animation valueAt:[_animation progress]];
    return (end * t) + ((1.0f - t) * start);
}

@end


@implementation RXChainingInterpolator

- (id)init {
    self = [super init];
    if (!self)
        return nil;
    
    _interpolators = [NSMutableArray new];
    
    return self;
}

- (void)dealloc {
    [_interpolators release];
    [_current release];
    [super dealloc];
}

- (void)addInterpolator:(id<RXInterpolator>)interpolator {
    if ([_interpolators count] == 0 && !_current)
        _current = [interpolator retain];
    else
        [_interpolators insertObject:interpolator atIndex:0];
}

- (void)_updateCurrent {
    if ([_interpolators count] == 0)
        return;
    
    [_current release];
    _current = [[_interpolators lastObject] retain];
    [_interpolators removeLastObject];
    [[_current animation] startNow];
}

- (RXAnimation*)animation {
    if (!_current || [_current isDone])
        [self _updateCurrent];
    if (!_current)
        return nil;
    return [[[_current animation] retain] autorelease];
}

- (float)value {
    if (!_current || [_current isDone])
        [self _updateCurrent];
    if (!_current)
        return 0.0f;
    return [_current value];
}

- (BOOL)isDone {
    if (!_current || [_current isDone])
        [self _updateCurrent];
    return ([_interpolators count] == 0 && (!_current || [_current isDone])) ? YES : NO;
}

@end
