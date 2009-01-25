//
//  RXCardExecutionProtocol.h
//  rivenx
//
//  Created by Jean-Francois Roy on 05/05/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RXHotspot.h"
#import "RXRivenScriptProtocol.h"

@protocol RXCardExecutionProtocol
- (void)setRivenScriptHandler:(id<RXRivenScriptProtocol>)handler;

- (void)prepareForRendering;
- (void)startRendering;
- (void)stopRendering;

- (NSArray*)activeHotspots;
- (void)mouseInsideHotspot:(RXHotspot*)hotspot;
- (void)mouseExitedHotspot:(RXHotspot*)hotspot;
- (void)mouseDownInHotspot:(RXHotspot*)hotspot;
- (void)mouseUpInHotspot:(RXHotspot*)hotspot;
@end
