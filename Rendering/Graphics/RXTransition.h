//
//  RXTransition.h
//  rivenx
//
//  Created by Jean-Francois Roy on 03/11/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "RXRendering.h"

enum {
    RXTransitionSlide,
    RXTransitionDissolve,
};
typedef uint8_t RXTransitionType;

enum {
    RXTransitionLeft = 0,
    RXTransitionRight,
    RXTransitionTop,
    RXTransitionBottom,
};
typedef uint8_t RXTransitionDirection;

enum {
    RXTransitionPushNew = 0x1,
    RXTransitionPushOld = 0x2,
};
typedef uint8_t RXTransitionOptions;

enum {
    RXTransitionCurveLinear = 0x1,
    RXTransitionCurveSquareSine = 0x2,
};
typedef uint8_t RXTransitionCurves;

@interface RXTransition : NSObject {
@public
    RXTransitionType type;
    RXTransitionDirection direction;
    BOOL pushNew;
    BOOL pushOld;
    
    NSRect region;
    
    GLuint sourceTexture;
    
    uint64_t startTime;
    double duration;
    RXTransitionCurves curve;
}

- (id)initWithCode:(uint16_t)code region:(NSRect)rect;
- (id)initWithType:(RXTransitionType)t direction:(RXTransitionDirection)d region:(NSRect)rect;
- (id)initWithType:(RXTransitionType)t direction:(RXTransitionDirection)d;
- (id)initWithType:(RXTransitionType)t direction:(RXTransitionDirection)d options:(RXTransitionOptions)options;

// designated initializer
- (id)initWithType:(RXTransitionType)t direction:(RXTransitionDirection)d options:(RXTransitionOptions)options region:(NSRect)rect;

- (BOOL)isPrimed;
- (void)primeWithSourceTexture:(GLuint)texture outputTime:(const CVTimeStamp*)outputTime;

- (float)applyAnimationCurve:(float)t;

@end
