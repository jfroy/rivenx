//
//	RXTransition.h
//	rivenx
//
//	Created by Jean-Francois Roy on 03/11/2007.
//	Copyright 2007 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

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
}

- (id)initWithCode:(uint16_t)code region:(NSRect)rect;

- (BOOL)isPrimed;

- (void)primeWithSourceTexture:(GLuint)texture outputTime:(const CVTimeStamp*)outputTime;

@end
