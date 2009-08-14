//
//  RXStateCompositor.h
//  rivenx
//
//  Created by Jean-Francois Roy on 8/10/07.
//  Copyright 2007 Apple, Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <pthread.h>
#import <libkern/OSAtomic.h>

#import "Rendering/RXRendering.h"
#import "Rendering/Animation/RXInterpolator.h"
#import "States/RXRenderState.h"


@interface RXStateCompositor : NSResponder <RXRenderingProtocol> {
    BOOL _toreDown;
    
    NSMutableArray* _states;
    NSMapTable* _state_map;
    
    NSArray* _renderStates;
    
    GLuint _compositing_program;
    GLint _texture_units_uniform;
    GLint _texture_blend_weights_uniform;
    GLfloat _texture_blend_weights[4];
    
    GLuint _compositing_vao;
    GLfloat vertex_coords[8];
    GLfloat tex_coords[8];
    GLfloat front_color[4];
    
    RXInterpolator* _fade_interpolator;
    NSInvocation* _fade_animation_callback;
    
    OSSpinLock _render_lock;
}

- (void)addState:(RXRenderState*)state opacity:(GLfloat)opacity;

- (void)fadeInState:(RXRenderState*)state over:(NSTimeInterval)duration completionDelegate:(id)delegate completionSelector:(SEL)completionSelector;
- (void)fadeOutState:(RXRenderState*)state over:(NSTimeInterval)duration completionDelegate:(id)delegate completionSelector:(SEL)completionSelector;

@end
