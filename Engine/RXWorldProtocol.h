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

#import "Engine/RXStack.h"
#import "Rendering/RXRendering.h"
#import "Rendering/Graphics/RXStateCompositor.h"
#import "Engine/RXGameState.h"


@protocol RXWorldProtocol <NSObject>
- (NSThread*)scriptThread;
- (NSThread*)animationThread;

- (MHKArchive*)extraBitmapsArchive;
- (NSDictionary*)extraBitmapsDescriptor;

- (RXStateCompositor*)stateCompositor;
- (void*)audioRenderer;

- (RXRenderState*)cyanMovieRenderState;
- (RXRenderState*)cardRenderState;
- (RXRenderState*)creditsRenderState;

- (RXGameState*)gameState;

- (NSCursor*)defaultCursor;
- (NSCursor*)openHandCursor;
- (NSCursor*)invisibleCursor;
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

CF_INLINE uint32_t RXEngineGetUInt32(NSString* path) {
	id o = [g_world valueForKeyPath:path];
	if (!o)
		return 0;
	return (uint32_t)[o unsignedIntValue];
}

CF_INLINE void RXEngineSetUInt32(NSString* path, uint32_t value) {
	[g_world setValue:[NSNumber numberWithInt:value] forKeyPath:path];
}

__END_DECLS

#endif // __OBJC__
