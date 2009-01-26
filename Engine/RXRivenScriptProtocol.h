/*
 *	RXRivenScriptProtocol.h
 *	rivenx
 *
 *	Created by Jean-Francois Roy on 01/02/2006.
 *	Copyright 2006 MacStorm. All rights reserved.
 *
 */

#import <Foundation/Foundation.h>

#import "Rendering/RXRendering.h"
#import "Rendering/Audio/RXSoundGroup.h"
#import "Rendering/Graphics/RXTransition.h"
#import "Rendering/Graphics/RXPicture.h"
#import "Rendering/Graphics/RXMovie.h"


@class RXCard;

@protocol RXRivenScriptProtocol <NSObject>
- (void)activateSoundGroup:(RXSoundGroup*)soundGroup;
- (void)playDataSound:(RXDataSound*)sound;

- (NSRect)mouseVector;
- (void)enableHotspotHandling;
- (void)disableHotspotHandling;
- (void)updateHotspotState;

- (void)queuePicture:(RXPicture*)picture;
- (void)queueSpecialEffect:(rx_card_sfxe*)sfxe owner:(id)owner;
- (void)queueTransition:(RXTransition*)transition;

- (void)enableMovie:(RXMovie*)movie;
- (void)disableMovie:(RXMovie*)movie;
- (void)disableAllMovies;

- (void)swapRenderState:(RXCard*)sender;

- (void)setActiveCardWithStack:(NSString *)stackKey ID:(uint16_t)cardID waitUntilDone:(BOOL)wait;
@end
