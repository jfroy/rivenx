//
//  RXScriptEngine.h
//  rivenx
//
//  Created by Jean-Francois Roy on 31/01/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <mach/semaphore.h>

#import <Foundation/Foundation.h>

#import "RXCard.h"
#import "RXScriptEngineProtocols.h"

#import "Rendering/Audio/RXSoundGroup.h"


@interface RXScriptEngine : NSObject <RXScriptEngineProtocol> {
	__weak id<RXScriptEngineControllerProtocol> controller;
	RXCard* card;
	
	// program execution
	uint32_t _programExecutionDepth;
	uint16_t _previousOpcode;
	BOOL _queuedAPushTransition;
	BOOL _abortProgramExecution;

	NSMutableString* logPrefix;
	BOOL _disableScriptLogging;
	
	NSMutableArray* _activeHotspots;
	OSSpinLock _activeHotspotsLock;
	BOOL _did_hide_mouse;
	
	// rendering support
	NSMapTable* _dynamicPictureMap;
	NSMapTable* code2movieMap;
	semaphore_t _moviePlaybackSemaphore;
	RXSoundGroup* _synthesizedSoundGroup;
	
	BOOL _renderStateSwapsEnabled;
	BOOL _didActivatePLST;
	BOOL _didActivateSLST;
	
	// gameplay support
	uint32_t sliders_state;
}

- (id)initWithController:(id<RXScriptEngineControllerProtocol>)ctlr;

@end
