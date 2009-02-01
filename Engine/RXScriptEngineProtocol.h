//
//  RXScriptEngineProtocol.h
//  rivenx
//
//  Created by Jean-Francois Roy on 05/05/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RXHotspot.h"
#import "RXCardProtocols.h"

@protocol RXScriptEngineProtocol <NSObject>
- (void)prepareForRendering;
- (void)startRendering;
- (void)stopRendering;

- (NSArray*)activeHotspots;
- (void)mouseInsideHotspot:(RXHotspot*)hotspot;
- (void)mouseExitedHotspot:(RXHotspot*)hotspot;
- (void)mouseDownInHotspot:(RXHotspot*)hotspot;
- (void)mouseUpInHotspot:(RXHotspot*)hotspot;
@end


@protocol RXScriptEngineControllerProtocol <RXCardEventsHandlerProtocol, RXCardRendererProtocol>
- (void)setActiveCardWithStack:(NSString*)stackKey ID:(uint16_t)cardID waitUntilDone:(BOOL)wait;
@end
