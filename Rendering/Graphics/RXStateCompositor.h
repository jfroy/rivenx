//
//	RXStateCompositor.h
//	rivenx
//
//	Created by Jean-Francois Roy on 8/10/07.
//	Copyright 2007 Apple, Inc. All rights reserved.
//

#import <pthread.h>

#import "RXRendering.h"
#import "RXRenderState.h"


@interface RXStateCompositor : NSResponder <RXRenderingProtocol> {
	BOOL _toreDown;
	
	NSMutableArray* _states;
	NSMapTable* _state_map;
	
	NSArray* _renderStates;
	
	GLuint _compositor_program;
	GLint _texture_units_uniform;
	GLint _texture_blend_weights_uniform;
	GLfloat _texture_blend_weights[4];
	
	GLfloat vertex_coords[8];
	GLfloat tex_coords[8];
	GLfloat front_color[4];
	
@public
	// THIS IS PUBLIC ONLY FOR RENDER STATES
	GLuint _fbo;
}

- (void)addState:(RXRenderState*)state opacity:(GLfloat)opacity;
- (void)setOpacity:(GLfloat)opacity ofState:(RXRenderState*)state;

// event forwarding
- (void)mouseDown:(NSEvent*)theEvent;
- (void)mouseUp:(NSEvent*)theEvent;
- (void)mouseMoved:(NSEvent*)theEvent;
- (void)mouseDragged:(NSEvent*)theEvent;

@end
