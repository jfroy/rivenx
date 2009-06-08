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
    uint16_t _previous_opcodes[2];
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
    
    int32_t _screen_update_disable_counter;
    BOOL _doing_screen_update;
    BOOL _didActivatePLST;
    BOOL _didActivateSLST;
    
    GLuint tiny_marble_atlas;
    
    // gameplay support
    RXHotspot* _current_hotspot;
    
    uint32_t sliders_state;
    rx_point_t dome_slider_background_position;
    
    uint16_t blue_marble_tBMP;
    rx_core_rect_t blue_marble_initial_rect;
    uint16_t green_marble_tBMP;
    rx_core_rect_t green_marble_initial_rect;
    uint16_t orange_marble_tBMP;
    rx_core_rect_t orange_marble_initial_rect;
    uint16_t violet_marble_tBMP;
    rx_core_rect_t violet_marble_initial_rect;
    uint16_t red_marble_tBMP;
    rx_core_rect_t red_marble_initial_rect;
    uint16_t yellow_marble_tBMP;
    rx_core_rect_t yellow_marble_initial_rect;
    
    NSTimer* prison_viewer_timer;
    CFAbsoluteTime whark_solo_done_ts;
}

- (id)initWithController:(id<RXScriptEngineControllerProtocol>)ctlr;

@end
