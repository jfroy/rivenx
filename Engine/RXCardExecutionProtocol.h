//
//  RXCardExecutionProtocol.h
//  rivenx
//
//  Created by Jean-Francois Roy on 05/05/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RXRivenScriptProtocol.h"

@protocol RXCardExecutionProtocol
- (void)setRivenScriptHandler:(id<RXRivenScriptProtocol>)handler;

- (void)prepareForRendering;
- (void)startRendering;
- (void)stopRendering;

- (void)finalizeRenderStateSwap;
@end
