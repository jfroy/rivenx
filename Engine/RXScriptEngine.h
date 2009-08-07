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
    BOOL _abortProgramExecution;
    
    NSMutableString* logPrefix;
    BOOL _disableScriptLogging;
    
    NSMutableArray* _active_hotspots;
    OSSpinLock _active_hotspots_lock;
    BOOL _did_hide_mouse;
    
    // rendering support
    NSMutableDictionary* _dynamic_picture_map;
    NSMapTable* code2movieMap;
    semaphore_t _moviePlaybackSemaphore;
    RXSoundGroup* _synthesizedSoundGroup;
    NSMutableSet* _movies_to_reset;
    NSTimer* _movie_collection_timer;
    
    int32_t _screen_update_disable_counter;
    BOOL _doing_screen_update;
    BOOL _did_activate_plst;
    BOOL _did_activate_slst;
    BOOL _disable_screen_update_programs;
    
    GLuint tiny_marble_atlas;
    
    // gameplay support
    RXHotspot* _current_hotspot;
    NSTimer* event_timer;
    
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
    
    uint16_t whark_solo_card;
    BOOL played_one_whark_solo;
    
    NSRect trapeze_rect;
    
    uint16_t frog_trap_card;
}

- (id)initWithController:(id<RXScriptEngineControllerProtocol>)ctlr;

@end
