//
//  RXScriptEngineProtocol.h
//  rivenx
//
//  Created by Jean-Francois Roy on 05/05/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "Engine/RXHotspot.h"
#import "Engine/RXCardProtocols.h"

@protocol RXScriptEngineProtocol <NSObject>
- (void)setCard:(RXCard*)c;

- (void)openCard;
- (void)startRendering;
- (void)closeCard;

- (NSArray*)activeHotspots;
- (void)mouseInsideHotspot:(RXHotspot*)hotspot;
- (void)mouseExitedHotspot:(RXHotspot*)hotspot;
- (void)mouseDownInHotspot:(RXHotspot*)hotspot;
- (void)mouseUpInHotspot:(RXHotspot*)hotspot;
@end


@protocol RXScriptEngineControllerProtocol <RXCardEventsHandlerProtocol, RXCardRendererProtocol>
- (void)setActiveCardWithSimpleDescriptor:(RXSimpleCardDescriptor*)scd waitUntilDone:(BOOL)wait;
- (void)setActiveCardWithStack:(NSString*)stackKey ID:(uint16_t)cardID waitUntilDone:(BOOL)wait;
@end
