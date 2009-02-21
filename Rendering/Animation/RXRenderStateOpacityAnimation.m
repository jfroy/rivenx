//
//  RXRenderStateOpacityAnimation.m
//  rivenx
//
//  Created by Jean-Francois Roy on 2008-06-20.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "RXRenderStateOpacityAnimation.h"

#import "RXWorldProtocol.h"


@implementation RXRenderStateOpacityAnimation

- (id)initWithState:(RXRenderState*)state targetOpacity:(float)opacity duration:(NSTimeInterval)duration {
	self = [super initWithDuration:duration animationCurve:NSAnimationEaseInOut];
	if (!self) return nil;
	
	_compositor = [g_world stateCompositor];
	_state = [state retain];
	
	_start = [_compositor opacityForState:_state];
	_end = opacity;
	
	return self;
}

- (void)dealloc {
	[_state release];
	
	[super dealloc];
}

- (void)setCurrentProgress:(NSAnimationProgress)progress {
	[super setCurrentProgress:progress];
	
	GLfloat t = [self currentValue];
	GLfloat v = (t * _end) + ((1.0f - t) * _start);
	[_compositor setOpacity:v ofState:_state];
}

@end
