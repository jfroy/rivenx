//
//	RXState.m
//	rivenx
//
//	Created by Jean-Francois Roy on 11/12/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import "RXRenderState.h"


@implementation RXRenderState

- (id)init {
	self = [super init];
	if (!self) return nil;
	
	_renderRect = CGRectNull;
	
	return self;
}

- (void)dealloc {
#if defined(DEBUG)
	RXOLog(@"deallocating");
#endif
	[super dealloc];
}

- (id)delegate {
	return _delegate;
}

- (void)setDelegate:(id)delegate {
	_delegateFlags.stateDidDiffuse = [delegate respondsToSelector:@selector(stateDidDiffuse:)];
	_delegate = delegate;
}

- (void)arm {
#if defined(DEBUG)
	RXOLog(@"arming");
#endif

	_armed = YES;
}

- (void)diffuse {
	_armed = NO;
	if(_delegateFlags.stateDidDiffuse) [_delegate stateDidDiffuse:self];
	
#if defined(DEBUG)
	RXOLog(@"did diffuse");
#endif
}

- (BOOL)isArmed {
	return _armed;
}

- (CGRect)renderRect {
	return _renderRect;
}

- (void)setRenderRect:(CGRect)rect {
	_renderRect = rect;
}

- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx parent:(id)parent {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime parent:(id)parent {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
}

#pragma mark -

- (BOOL)acceptsFirstResponder {
	return YES;
}

- (BOOL)becomeFirstResponder {
#if defined(DEBUG)
	RXOLog(@"became first responder");
#endif
	return YES;
}

- (BOOL)resignFirstResponder {
	return !_armed;
}

#if defined(DEBUG)

- (void)mouseDown:(NSEvent *)theEvent {
	//RXOLog(@"Caught mouseDown");
}

- (void)rightMouseDown:(NSEvent *)theEvent {
	//RXOLog(@"Caught rightMouseDown");
}

- (void)otherMouseDown:(NSEvent *)theEvent {
	//RXOLog(@"Caught otherMouseDown");
}

- (void)mouseUp:(NSEvent *)theEvent {
	//RXOLog(@"Caught mouseUp");
}

- (void)rightMouseUp:(NSEvent *)theEvent {
	//RXOLog(@"Caught rightMouseUp");
}

- (void)otherMouseUp:(NSEvent *)theEvent {
	//RXOLog(@"Caught otherMouseUp");
}

- (void)mouseMoved:(NSEvent *)theEvent {
//	RXOLog(@"mouseMoved");
}

- (void)mouseDragged:(NSEvent *)theEvent {
	//RXOLog(@"Caught mouseDragged");
}

- (void)scrollWheel:(NSEvent *)theEvent {
	//RXOLog(@"Caught scrollWheel");
}

- (void)rightMouseDragged:(NSEvent *)theEvent {
	//RXOLog(@"Caught rightMouseDragged");
}

- (void)otherMouseDragged:(NSEvent *)theEvent {
	//RXOLog(@"Caught otherMouseDragged");
}

- (void)keyDown:(NSEvent *)theEvent {
	NSString* characters = [theEvent charactersIgnoringModifiers];
	unichar firstCharacter = [characters characterAtIndex:0];
	
#if defined(DEBUG)
	RXOLog(@"caught keyDown: 0x%x", firstCharacter);
#endif
}

- (void)keyUp:(NSEvent *)theEvent {
	//RXOLog(@"Caught keyUp");
}

- (void)flagsChanged:(NSEvent *)theEvent {
	//RXOLog(@"Caught flagsChanged");
}

#endif

@end
