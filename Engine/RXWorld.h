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
    NSURL* _worldBase;
    NSURL* _worldUserBase;
    
    NSDictionary* _extrasDescriptor;
    
    NSMapTable* _cursors;
    
    semaphore_t _threadInitSemaphore;
    NSThread* _scriptThread;
    
    
    NSView <RXWorldViewProtocol>* _worldView;
    NSWindow* _fullscreenWindow;
    NSWindow* _window;
    void* _audioRenderer;
    RXRenderState* _cardRenderer;
    
    RXGameState* _gameState;
    RXGameState* _gameStateToLoad;
    
    pthread_mutex_t _engineVariablesMutex;
    NSMutableDictionary* _engineVariables;
    
    NSApplicationPresentationOptions _defaultPresentationOptions;
    
    BOOL _tornDown;
    BOOL _renderingInitialized;
    BOOL _fullscreen;
}

+ (RXWorld*)sharedWorld;

- (void)tearDown;

- (NSURL*)worldBase;
- (NSURL*)worldUserBase;

- (RXGameState*)gameState;
- (BOOL)loadGameState:(RXGameState*)gameState error:(NSError**)error;

@end
