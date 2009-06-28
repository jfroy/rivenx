//
//  RXCardProtocols.h
//  rivenx
//
//  Created by Jean-Francois Roy on 01/02/2006.
//  Copyright 2006 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Rendering/RXRendering.h"
#import "Rendering/Audio/RXSoundGroup.h"
#import "Rendering/Graphics/RXTransition.h"
#import "Rendering/Graphics/RXPicture.h"
#import "Rendering/Graphics/RXMovie.h"


@class RXCard;

@protocol RXCardRendererProtocol <NSObject>
- (void)activateSoundGroup:(RXSoundGroup*)soundGroup;
- (void)playDataSound:(RXDataSound*)sound;

- (void)queuePicture:(RXPicture*)picture;

- (void)queueSpecialEffect:(rx_card_sfxe*)sfxe owner:(id)owner;
- (void)disableWaterSpecialEffect;
- (void)enableWaterSpecialEffect;

- (void)queueTransition:(RXTransition*)transition;
- (void)enableTransitionDequeueing;
- (void)disableTransitionDequeueing;

- (void)enableMovie:(RXMovie*)movie;
- (void)disableMovie:(RXMovie*)movie;
- (void)disableAllMovies;
- (void)disableAllMoviesOnNextScreenUpdate;

- (void)update;
@end


@protocol RXCardEventsHandlerProtocol <NSObject>
- (double)mouseTimestamp;
- (rx_event_t)lastMouseDownEvent;
- (NSRect)mouseVector;
- (void)resetMouseVector;

- (void)showMouseCursor;
- (void)hideMouseCursor;
- (void)setMouseCursor:(uint16_t)cursorID;

- (void)enableHotspotHandling;
- (void)disableHotspotHandling;
- (void)updateHotspotState;
@end
