//
//  RXMovieProxy.m
//  rivenx
//
//  Created by Jean-Francois Roy on 26/03/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "RXMovieProxy.h"


@implementation RXMovieProxy

- (id)init {
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (id)initWithArchive:(MHKArchive*)archive ID:(uint16_t)ID origin:(CGPoint)origin loop:(BOOL)loop owner:(id)owner {
	self = [super init];
	if (!self)
		return nil;
	
	_owner = owner;
	_archive = archive;
	_ID = ID;
	_origin = origin;
	_loop = loop;
	
	return self;
}

- (void)dealloc {
	[_movie release];
	[super dealloc];
}

- (void)_loadMovie {
	// WARNING: MUST RUN ON MAIN THREAD
	if (_movie)
		return;
	
	// FIXME: error handling in [RXProxyMovie _loadMovie]
	Movie movie = [_archive movieWithID:_ID error:NULL];
	_movie = [[RXMovie alloc] initWithMovie:movie disposeWhenDone:YES owner:_owner];
	
	// set movie attributes
	[_movie setWorkingColorSpace:[RXGetWorldView() workingColorSpace]];
	[_movie setOutputColorSpace:[RXGetWorldView() displayColorSpace]];
	[_movie setExpectedReadAheadFromDisplayLink:[RXGetWorldView() displayLink]];
	[_movie setLooping:_loop];
	
	// set render rect
	CGRect renderRect = [_movie renderRect];
	renderRect.origin.x = _origin.x;
	renderRect.origin.y = _origin.y - renderRect.size.height;
	[_movie setRenderRect:renderRect];
	
	// FIXME: set movie volume
}

+ (BOOL)instancesRespondToSelector:(SEL)aSelector {
	if ([super instancesRespondToSelector:aSelector])
		return YES;
	return [RXMovie instancesRespondToSelector:aSelector];
}

+ (NSMethodSignature*)instanceMethodSignatureForSelector:(SEL)aSelector {
	NSMethodSignature* signature = [super instanceMethodSignatureForSelector:aSelector];
	if (signature)
		return signature;
	return [RXMovie instanceMethodSignatureForSelector:aSelector];
}

- (BOOL)isKindOfClass:(Class)aClass {
	if ([super isKindOfClass:aClass])
		return YES;
	return [aClass isSubclassOfClass:[RXMovie class]];
}

- (BOOL)respondsToSelector:(SEL)aSelector {
	if ([super respondsToSelector:aSelector])
		return YES;
	return [RXMovie instancesRespondToSelector:aSelector];
}

- (NSMethodSignature*)methodSignatureForSelector:(SEL)aSelector {
	NSMethodSignature* signature = [super methodSignatureForSelector:aSelector];
	if (signature)
		return signature;
	return [RXMovie instanceMethodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation*)anInvocation {
	// if the movie has not been loaded yet, do that on the main thread
	if (!_movie)
		[self performSelectorOnMainThread:@selector(_loadMovie) withObject:nil waitUntilDone:YES];
	
	// forward the message to the movie
	[anInvocation invokeWithTarget:_movie]; 
}

#pragma mark -
#pragma mark common known selectors

- (id)owner {
	// we don't need to allocate the movie to respond to this method
	return _owner;
}

- (QTMovie*)movie {
	// if the movie has not been loaded yet, do that on the main thread
	if (!_movie)
		[self performSelectorOnMainThread:@selector(_loadMovie) withObject:nil waitUntilDone:YES];
	
	return [_movie movie];
}

- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx framebuffer:(GLuint)fbo {
	// if the movie has not been loaded yet, do that on the main thread
	if (!_movie)
		[self performSelectorOnMainThread:@selector(_loadMovie) withObject:nil waitUntilDone:YES];
	
	[_movie render:outputTime inContext:cgl_ctx framebuffer:fbo];
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime {
	// if the movie has not been loaded yet, do that on the main thread
	if (!_movie)
		[self performSelectorOnMainThread:@selector(_loadMovie) withObject:nil waitUntilDone:YES];
	
	[_movie performPostFlushTasks:outputTime];
}

@end
