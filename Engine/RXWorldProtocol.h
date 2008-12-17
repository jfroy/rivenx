/*
 *	RXWorldProtocol.h
 *	rivenx
 *
 *	Created by Jean-Francois Roy on 01/10/2005.
 *	Copyright 2005 MacStorm. All rights reserved.
 *
 */

#if !defined(__OBJC__)
#error RXWorldProtocol.h requires Objective-C
#else

#import <sys/cdefs.h>

#import <Foundation/Foundation.h>
#import <MHKKit/MHKKit.h>

#import "RXStack.h"
#import "RXRendering.h"
#import "RXStateCompositor.h"
#import "RXGameState.h"


@protocol RXWorldProtocol <NSObject>
- (NSThread*)stackThread;
- (NSThread*)scriptThread;
- (NSThread*)animationThread;

- (MHKArchive*)extraBitmapsArchive;
- (NSDictionary*)extraBitmapsDescriptor;

- (NSArray*)activeStacks;
- (RXStack*)activeStackWithKey:(NSString*)key;

- (void)loadStackWithKey:(NSString*)stackKey waitUntilDone:(BOOL)waitFlag;

- (RXStateCompositor*)stateCompositor;
- (void*)audioRenderer;

- (RXRenderState*)cyanMovieRenderState;
- (RXRenderState*)cardRenderState;
- (RXRenderState*)creditsRenderState;

- (RXGameState*)gameState;

- (NSCursor*)defaultCursor;
- (NSCursor*)openHandCursor;
- (NSCursor*)cursorForID:(uint16_t)ID;
@end


__BEGIN_DECLS

extern NSObject <RXWorldProtocol>* g_world;

CF_INLINE BOOL RXEngineGetBool(NSString* path) {
	id o = [g_world valueForKeyPath:path];
	if (!o)
		return NO;
	return [o boolValue];
}

__END_DECLS

#endif // __OBJC__
