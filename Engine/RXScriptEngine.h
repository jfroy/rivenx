//
//  RXScriptEngine.h
//  rivenx
//
//  Created by Jean-Francois Roy on 31/01/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RXScriptEngineProtocol.h"


@interface RXScriptEngine : NSObject <RXScriptEngineProtocol> {
	__weak id<RXScriptEngineControllerProtocol> controller;

	NSMutableString* logPrefix;
	NSMapTable* code2movieMap;
	
	// rendering
	BOOL _renderStateSwapsEnabled;
	
	BOOL _didActivatePLST;
	BOOL _didActivateSLST;
	
	// program execution
	uint32_t _programExecutionDepth;
	uint16_t _lastExecutedProgramOpcode;
	BOOL _queuedAPushTransition;
	BOOL _did_hide_mouse;
}

- (void)initWithController:(id<RXScriptEngineControllerProtocol>)ctlr;

@end
