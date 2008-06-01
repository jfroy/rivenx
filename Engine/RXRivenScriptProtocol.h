/*
 *	RXRivenScriptProtocol.h
 *	rivenx
 *
 *	Created by Jean-Francois Roy on 01/02/2006.
 *	Copyright 2006 MacStorm. All rights reserved.
 *
 */

#import <Foundation/Foundation.h>

#import "RXSoundGroup.h"
#import "RXTransition.h"


@class RXCard;

@protocol RXRivenScriptProtocol <NSObject>
- (void)activateSoundGroup:(RXSoundGroup*)soundGroup;
- (void)playDataSound:(RXDataSound*)sound;

- (void)setProcessUIEvents:(BOOL)process;
- (void)resetHotspotState;
- (void)setExecutingBlockingAction:(BOOL)blocking;

- (void)queueTransition:(RXTransition*)transition;

- (void)swapRenderState:(RXCard*)sender;
- (void)swapMovieRenderState:(RXCard*)sender;

- (void)setActiveCardWithStack:(NSString *)stackKey ID:(uint16_t)cardID waitUntilDone:(BOOL)wait;
@end
