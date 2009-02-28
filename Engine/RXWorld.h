//
//	RXWorld.h
//	rivenx
//
//	Created by Jean-Francois Roy on 25/08/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <mach/semaphore.h>

#import <pthread.h>

#import <Cocoa/Cocoa.h>
#import <MHKKit/MHKKit.h>

#import "RXWorldProtocol.h"

#import "RXGameState.h"
#import "RXEditionManager.h"

#import "RXRendering.h"
#import "RXRenderState.h"

#import "RXStack.h"


@interface RXWorld : NSObject <RXWorldProtocol> {
	BOOL _tornDown;
	
	// world location
	NSURL* _worldBase;
	NSURL* _worldUserBase;
	
	// extras data store
	MHKArchive* _extraBitmapsArchive;
	NSDictionary* _extrasDescriptor;
	
	// cursors
	NSMapTable* _cursors;
	
	// threading
	semaphore_t _threadInitSemaphore;
	
	pthread_rwlock_t _stackCreationLock;
	
	NSMutableDictionary* _activeStacks;
	pthread_rwlock_t _activeStacksLock;
	
	// riven script
	NSThread* _scriptThread;
	
	// animation
	NSThread* _animationThread;
	
	// rendering
	BOOL _rendering_initialized;
	NSView <RXWorldViewProtocol>* _worldView;
	void* _audioRenderer;
	RXStateCompositor* _stateCompositor;
	
	// rendering states
	RXRenderState* _cardState;
	RXRenderState* _cyanMovieState;
	RXRenderState* _creditsState;
	
	// game state
	RXGameState* _gameState;
	RXGameState* _gameStateToLoad;
	
	// engine variables
	pthread_mutex_t _engineVariablesMutex;
	NSMutableDictionary* _engineVariables;
}

+ (RXWorld*)sharedWorld;

- (void)tearDown;

- (NSURL*)worldBase;
- (NSURL*)worldUserBase;

- (RXGameState*)gameState;
- (BOOL)loadGameState:(RXGameState*)gameState error:(NSError**)error;

@end
