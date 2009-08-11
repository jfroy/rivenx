//
//  RXTransition.m
//  rivenx
//
//  Created by Jean-Francois Roy on 03/11/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import "RXTransition.h"
#import "RXTiming.h"

static NSString* _kRXTransitionDirectionNames[4] = {
    @"RXTransitionLeft",
    @"RXTransitionRight",
    @"RXTransitionTop",
    @"RXTransitionBottom",
};


@implementation RXTransition

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithCode:(uint16_t)code region:(NSRect)rect {
    RXTransitionType t;
    RXTransitionDirection d = 0;
    RXTransitionOptions o = 0;
    
    if (code <= 15) {
        t = RXTransitionSlide;
        d = code & 0x3;
        o = ((code & 0x4) ? RXTransitionPushNew : 0) | ((code & 0x8) ? RXTransitionPushOld : 0);
    } else if (code == 16 || code == 17)
        t = RXTransitionDissolve;
    else {
        [self release];
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"INVALID TRANSITION CODE" userInfo:nil];
    }
    
    return [self initWithType:t direction:d options:o region:rect];
}

- (id)initWithType:(RXTransitionType)t direction:(RXTransitionDirection)d region:(NSRect)rect {
    return [self initWithType:t direction:d options:0 region:rect];
}

- (id)initWithType:(RXTransitionType)t direction:(RXTransitionDirection)d {
    return [self initWithType:t direction:d options:0 region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
}

- (id)initWithType:(RXTransitionType)t direction:(RXTransitionDirection)d options:(RXTransitionOptions)options {
    return [self initWithType:t direction:d options:options region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
}

- (id)initWithType:(RXTransitionType)t direction:(RXTransitionDirection)d options:(RXTransitionOptions)options region:(NSRect)rect {
    self = [super init];
    if (!self)
        return nil;
    
    type = t;
    direction = d;
    
    pushNew = (options & RXTransitionPushNew) ? YES : NO;
    pushOld = (options & RXTransitionPushOld) ? YES : NO;
    
    region = rect;
    
    startTime = 0;
    duration = kRXTransitionDuration;
    
    // by default, linear for dissolves, square sine for slides
    if (type == RXTransitionDissolve)
        curve = RXTransitionCurveLinear;
    else
        curve = RXTransitionCurveSquareSine;
    
    return self;
}

- (void)dealloc {
    [source_texture release];
    [super dealloc];
}

- (NSString*)description {
    if (type == RXTransitionSlide) {
        NSString* directionString = _kRXTransitionDirectionNames[direction];
        return [NSString stringWithFormat: @"%@ {type = RXTransitionSlide, direction = %@, pushNew = %d, pushOld = %d}", [super description], directionString, pushNew, pushOld];
    } else {
        return [NSString stringWithFormat: @"%@ {type = RXTransitionDissolve}", [super description]];
    }
}

- (BOOL)isPrimed {
    return (source_texture != nil) ? YES : NO;
}

- (void)primeWithSourceTexture:(RXTexture*)texture outputTime:(const CVTimeStamp*)output_time {
    source_texture = [texture retain];
    startTime = output_time->hostTime;
#if defined(DEBUG)
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"primed with texture %@ at %lu", source_texture, startTime);
#endif
}

- (float)applyAnimationCurve:(float)t {
    switch (curve) {
        case RXTransitionCurveSquareSine:
        {
            double sine = sin(M_PI_2 * t);
            return sine * sine;
        }
        case RXTransitionCurveLinear:
        default:
            return t;
    }
}

@end
