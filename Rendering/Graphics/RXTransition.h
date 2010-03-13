//
//  RXTransition.h
//  rivenx
//
//  Created by Jean-Francois Roy on 03/11/2007.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "Rendering/Animation/RXAnimation.h"
#import "Rendering/Graphics/RXTexture.h"


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

@interface RXTransition : NSObject {
@public
    RXTransitionType type;
    RXTransitionDirection direction;
    BOOL pushNew;
    BOOL pushOld;
    
    NSRect region;
    
    RXTexture* source_texture;
    RXAnimation* animation;
}

- (id)initWithCode:(uint16_t)code region:(NSRect)rect;
- (id)initWithType:(RXTransitionType)t direction:(RXTransitionDirection)d region:(NSRect)rect;
- (id)initWithType:(RXTransitionType)t direction:(RXTransitionDirection)d;
- (id)initWithType:(RXTransitionType)t direction:(RXTransitionDirection)d options:(RXTransitionOptions)options;

// designated initializer
- (id)initWithType:(RXTransitionType)t direction:(RXTransitionDirection)d options:(RXTransitionOptions)options region:(NSRect)rect;

- (BOOL)isPrimed;
- (void)primeWithSourceTexture:(RXTexture*)texture;

@end
