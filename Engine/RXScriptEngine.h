//
//  RXScriptEngine.h
//  rivenx
//
//  Created by Jean-Francois Roy on 31/01/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <mach/semaphore.h>

#import <Cocoa/Cocoa.h>

#import "Engine/RXCard.h"
#import "Engine/RXScriptEngineProtocols.h"

#import "Rendering/Audio/RXSoundGroup.h"
#import "Rendering/Graphics/RXMovieProxy.h"
#import "Rendering/Graphics/RXTexture.h"


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
    NSMutableDictionary* _dynamic_texture_cache;
    NSMutableDictionary* _picture_cache;
    
    NSMapTable* code2movieMap;
    semaphore_t _moviePlaybackSemaphore;
    NSMutableSet* _movies_to_reset;
    RXMovieProxy* _blocking_movie;
    
    RXSoundGroup* _synthesizedSoundGroup;
    
    int32_t _screen_update_disable_counter;
    BOOL _doing_screen_update;
    BOOL _did_activate_plst;
    BOOL _did_activate_slst;
    BOOL _disable_screen_update_programs;
    BOOL _schedule_movie_proxy_reset;
    BOOL _reset_movie_proxies;
    
    RXTexture* tiny_marble_atlas;
    
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
    
    uint16_t frog_trap_card;
    uint16_t rebel_prison_window_card;
    uint16_t whark_solo_card;
    
    BOOL played_one_whark_solo;
    NSRect trapeze_rect;
}

- (id)initWithController:(id<RXScriptEngineControllerProtocol>)ctlr;

@end
