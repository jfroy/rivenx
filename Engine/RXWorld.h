//
//  RXWorld.h
//  rivenx
//
//  Created by Jean-Francois Roy on 25/08/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import <mach/semaphore.h>
#import <pthread.h>
#import <Cocoa/Cocoa.h>

#import "Engine/RXWorldProtocol.h"
#import "Engine/RXGameState.h"
#import "Rendering/RXRendering.h"
#import "States/RXRenderState.h"


@interface RXWorld : NSObject <RXWorldProtocol> {
    BOOL _tornDown;
    
    // world location
    NSURL* _worldBase;
    NSURL* _worldUserBase;
    
    // extras data store
    NSDictionary* _extrasDescriptor;
    
    // cursors
    NSMapTable* _cursors;
    
    // threading
    semaphore_t _threadInitSemaphore;
    NSThread* _scriptThread;
    
    // rendering
    BOOL _rendering_initialized;
    NSView <RXWorldViewProtocol>* _worldView;
    void* _audioRenderer;
    RXStateCompositor* _stateCompositor;
    
    // rendering states
    RXRenderState* _cardState;
    
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
