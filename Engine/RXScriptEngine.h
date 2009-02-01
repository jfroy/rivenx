//
//  RXScriptEngine.h
//  rivenx
//
//  Created by Jean-Francois Roy on 31/01/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RXCard.h"
#import "RXScriptEngineProtocols.h"

#import "Rendering/Audio/RXSoundGroup.h"


@interface RXScriptEngine : NSObject <RXScriptEngineProtocol> {
	__weak id<RXScriptEngineControllerProtocol> controller;
	RXCard* card;

	NSMutableString* logPrefix;
	BOOL _disableScriptLogging;
	
	NSMapTable* code2movieMap;
	
	// hotpots
	NSMutableArray* _activeHotspots;
	OSSpinLock _activeHotspotsLock;
	
	// rendering
	BOOL _renderStateSwapsEnabled;
	
	BOOL _didActivatePLST;
	BOOL _didActivateSLST;
	
	// program execution
	uint32_t _programExecutionDepth;
	uint16_t _lastExecutedProgramOpcode;
	BOOL _queuedAPushTransition;
	BOOL _did_hide_mouse;
	
	RXSoundGroup* _synthesizedSoundGroup;
}

- (id)initWithController:(id<RXScriptEngineControllerProtocol>)ctlr;

@end
