//
//	RXTransition.m
//	rivenx
//
//	Created by Jean-Francois Roy on 03/11/2007.
//	Copyright 2007 MacStorm. All rights reserved.
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
	self = [super init];
	if (!self)
		return nil;
	
	if (code <= 15) {
		type = RXTransitionSlide;
		direction = code & 0x3;
		pushNew = (code & 0x4) ? YES : NO;
		pushOld = (code & 0x8) ? YES : NO;
	} else if (code == 16 || code == 17) type = RXTransitionDissolve;
	else {
		[self release];
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"INVALID TRANSITION CODE" userInfo:nil];
	}
	
	region = rect;
	
	startTime = 0;
	duration = kRXTransitionDuration;
	
	return self;
}

- (id)initWithType:(RXTransitionType)transitionType direction:(RXTransitionDirection)transitionDirection region:(NSRect)rect {
	self = [super init];
	if (!self)
		return nil;
	
	type = transitionType;
	direction = transitionDirection;
	
	region = rect;
	
	startTime = 0;
	duration = kRXTransitionDuration;
	
	return self;
}

- (void)dealloc {
	if (sourceTexture) {
		CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
		CGLLockContext(cgl_ctx);
		glDeleteTextures(1, &sourceTexture);
		CGLUnlockContext(cgl_ctx);
	}
	
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
	return (sourceTexture != 0) ? YES : NO;
}

- (void)primeWithSourceTexture:(GLuint)texture outputTime:(const CVTimeStamp*)outputTime {
	sourceTexture = texture;
	startTime = outputTime->hostTime;
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"primed with texture ID %u at %lu", sourceTexture, startTime);
#endif
}

@end
