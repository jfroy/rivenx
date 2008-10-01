//
//	RXStateCompositor.mm
//	rivenx
//
//	Created by Jean-Francois Roy on 8/10/07.
//	Copyright 2007 Apple, Inc. All rights reserved.
//

#import <OpenGL/CGLMacro.h>

#import "RXAtomic.h"

#import "RXStateCompositor.h"
#import "RXWorldProtocol.h"

#import "Rendering/Graphics/GL/GLShaderProgramManager.h"

#import "RXRenderStateOpacityAnimation.h"


@interface RXRenderStateCompositionDescriptor : NSObject {
@public
	RXRenderState* state;
	GLfloat opacity;
	
	rx_render_dispatch_t render;
	rx_post_flush_tasks_dispatch_t post_flush;
	
	GLuint fbo;
	GLuint texture;
}
@end

@implementation RXRenderStateCompositionDescriptor

- (void)dealloc {
	// WARNING: ASSUMES THE CONTEXT IS LOCKED
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	
	glDeleteFramebuffersEXT(1, &fbo);
	glDeleteTextures(1, &texture);
	
	[state release];
	
	[super dealloc];
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime {
	// This method only forwards
	[state performPostFlushTasks:outputTime];
}

@end


@implementation RXStateCompositor

- (id)init {
	self = [super init];
	if (!self) return nil;
	
	NSError* error;
	
	_states = [[NSMutableArray alloc] initWithCapacity:0x10];
	_state_map = NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks, NSNonRetainedObjectMapValueCallBacks, 0);
	_animationCompletionInvocations = NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks, NSObjectMapValueCallBacks, 0);
	
	_renderStates = [_states copy];
	
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	CGLLockContext(cgl_ctx);
	
	// render state composition shader program
	_compositing_program = [[GLShaderProgramManager sharedManager] standardProgramWithFragmentShaderName:@"state_compositor" extraSources:nil epilogueIndex:0 context:cgl_ctx error:&error];
	if (_compositing_program == 0)
		@throw [NSException exceptionWithName:@"RXStateCompositorException" reason:@"Riven X was unable to load the render state compositor shader program." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	_texture_units_uniform = glGetUniformLocation(_compositing_program, "texture_units"); glReportError();
	_texture_blend_weights_uniform = glGetUniformLocation(_compositing_program, "texture_blend_weights"); glReportError();
	
	glUseProgram(_compositing_program); glReportError();
	
	GLint samplers[4] = {0, 1, 2, 3};
	glUniform1iv(_texture_units_uniform, 4, samplers); glReportError();
	glUniform4f(_texture_blend_weights_uniform, 0.0f, 0.0f, 0.0f, 0.0f); glReportError();
	
	glUseProgram(0);
	
	// configure the compositing VAO
	glGenVertexArraysAPPLE(1, &_compositing_vao); glReportError();
	glBindVertexArrayAPPLE(_compositing_vao); glReportError();
	
	glBindBuffer(GL_ARRAY_BUFFER, 0);
	
	glEnableClientState(GL_VERTEX_ARRAY); glReportError();
	glVertexPointer(2, GL_FLOAT, 0, vertex_coords); glReportError();
	
	glBindVertexArrayAPPLE(0); glReportError();
	
	CGLUnlockContext(cgl_ctx);
	
	front_color[0] = front_color[1] = front_color[2] = front_color[3] = 1.0f;
	_texture_blend_weights[0] = _texture_blend_weights[1] = _texture_blend_weights[2] = _texture_blend_weights[3] = 0.0f;
	
	// we need to listen for OpenGL reshape notifications
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_reshapeGL:) name:@"RXOpenGLDidReshapeNotification" object:nil];
	
	return self;
}

- (void)tearDown {
	if (_toreDown) return;
	_toreDown = YES;
#if defined(DEBUG)
	RXOLog(@"tearing down");
#endif
	
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	CGLLockContext(cgl_ctx);
	
	[_states removeAllObjects];
	NSResetMapTable(_state_map);
	
	glDeleteVertexArraysAPPLE(1, &_compositing_vao);
	glDeleteProgram(_compositing_program);
		
	CGLUnlockContext(cgl_ctx);
}

- (void)dealloc {
	[self tearDown];
	
	[_states release];
	NSFreeMapTable(_state_map);
	[_renderStates release];
	NSFreeMapTable(_animationCompletionInvocations);
	
	[super dealloc];
}

- (void)_reshapeGL:(NSNotification *)notification {
	// WARNING: IT IS ASSUMED THE CURRENT CONTEXT HAS BEEN LOCKED BY THE CALLER
#if defined(DEBUG)
	RXOLog(@"reshaping OpenGL");
#endif
	
	rx_size_t viewportSize = RXGetGLViewportSize();
	rx_rect_t contentRect = RXEffectiveRendererFrame();
	
	vertex_coords[0] = contentRect.origin.x;											vertex_coords[1] = contentRect.origin.y;
	vertex_coords[2] = vertex_coords[0];												vertex_coords[3] = vertex_coords[1] + contentRect.size.height;
	vertex_coords[4] = vertex_coords[2] + contentRect.size.width;						vertex_coords[5] = vertex_coords[3];
	vertex_coords[6] = vertex_coords[4];												vertex_coords[7] = vertex_coords[1];
	
	tex_coords[0] = 0.0f;																tex_coords[1] = 0.0f;
	tex_coords[2] = 0.0f;																tex_coords[3] = (GLfloat)kRXRendererViewportSize.height;
	tex_coords[4] = (GLfloat)kRXRendererViewportSize.width;								tex_coords[5] = (GLfloat)kRXRendererViewportSize.height;
	tex_coords[6] = (GLfloat)kRXRendererViewportSize.width;								tex_coords[7] = 0.0f;
}

- (void)_updateTextureBlendWeightsUniform {
	uint32_t state_count = [_states count];
	if (state_count > 0) {
		_texture_blend_weights[0] = ((RXRenderStateCompositionDescriptor*)[_states objectAtIndex:0])->opacity;
		if (state_count > 1) {
			_texture_blend_weights[1] = ((RXRenderStateCompositionDescriptor*)[_states objectAtIndex:1])->opacity;
			if (state_count > 2) {
				_texture_blend_weights[2] = ((RXRenderStateCompositionDescriptor*)[_states objectAtIndex:2])->opacity;
				if (state_count > 3) _texture_blend_weights[3] = ((RXRenderStateCompositionDescriptor*)[_states objectAtIndex:3])->opacity;
			}
		}
	}
}

- (void)addState:(RXRenderState*)state opacity:(GLfloat)opacity {
	// FIXME: render state compositor only supports 4 states at this time
	if ([_states count] == 4)
		return;
	
	// insert the state in the state responder chain
	if ([_states count])
		[state setNextResponder:((RXRenderStateCompositionDescriptor*)[_states lastObject])->state];
	
	// make a state composition descriptor
	RXRenderStateCompositionDescriptor* descriptor = [RXRenderStateCompositionDescriptor new];
	descriptor->state = [state retain];
	descriptor->opacity = opacity;
	descriptor->render = RXGetRenderImplementation([state class], RXRenderingRenderSelector);
	descriptor->post_flush = RXGetPostFlushTasksImplementation([state class], RXRenderingPostFlushTasksSelector);
	
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	CGLLockContext(cgl_ctx);
	
	glGenFramebuffersEXT(1, &(descriptor->fbo));
	glGenTextures(1, &(descriptor->texture));
	
	// bind the texture
	glBindTexture(GL_TEXTURE_RECTANGLE_ARB, descriptor->texture);
	glReportError();
	
	// texture parameters
	glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glReportError();
	
	// disable client storage because it's incompatible with allocating texture space with NULL (which is what we want to do for FBO color attachement textures)
	glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_FALSE);
	
	// allocate memory for the texture
	glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, kRXRendererViewportSize.width, kRXRendererViewportSize.height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
	glReportError();
	
	// color0 texture attach
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, descriptor->fbo); glReportError();
	glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_ARB, descriptor->texture, 0); glReportError();
		
	// completeness check
	GLenum status = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
	if (status != GL_FRAMEBUFFER_COMPLETE_EXT) {
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"render state FBO not complete, status 0x%04x\n", (unsigned int)status);
		[descriptor release];
		return;
	}
	
	// re-enable client storage
	glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
	
	// configure the tex coord array for the new state
	glBindVertexArrayAPPLE(_compositing_vao); glReportError();
	
	glBindBuffer(GL_ARRAY_BUFFER, 0);
	
	glClientActiveTexture(GL_TEXTURE0 + [_states count]);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY); glReportError();
	glTexCoordPointer(2, GL_FLOAT, 0, tex_coords); glReportError();
	
	glBindVertexArrayAPPLE(0); glReportError();
	
	CGLUnlockContext(cgl_ctx);
	
	// add the state descriptor to the array of state descriptors
	[_states addObject:descriptor];
	NSMapInsert(_state_map, state, descriptor);
	
	// update the texture blend weight
	[self _updateTextureBlendWeightsUniform];
	
	// swap
	NSArray* old = _renderStates;
	_renderStates = [_states copy];
	
	[old release];
	[descriptor release];
}

- (GLfloat)opacityForState:(RXRenderState*)state {
	RXRenderStateCompositionDescriptor* descriptor = (RXRenderStateCompositionDescriptor*)NSMapGet(_state_map, state);
	if (!descriptor) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"%@ is not composited by this compositor" userInfo:nil];
	
	return descriptor->opacity;
}

- (void)setOpacity:(GLfloat)opacity ofState:(RXRenderState *)state {
	RXRenderStateCompositionDescriptor* descriptor = (RXRenderStateCompositionDescriptor*)NSMapGet(_state_map, state);
	if (!descriptor) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"%@ is not composited by this compositor" userInfo:nil];
	
	// change the opacity in the render state descriptor
	descriptor->opacity = opacity;
	
	// update the texture blend weight
	[self _updateTextureBlendWeightsUniform];
}

- (void)animationDidEnd:(NSAnimation*)animation {
	[(NSInvocation*)NSMapGet(_animationCompletionInvocations, animation) invoke];
	NSMapRemove(_animationCompletionInvocations, animation);
	
	if (_currentFadeAnimation == animation) _currentFadeAnimation = nil;
	[animation release];
}

- (void)animationDidStop:(NSAnimation*)animation {
	[(NSInvocation*)NSMapGet(_animationCompletionInvocations, animation) invoke];
	NSMapRemove(_animationCompletionInvocations, animation);
	
	if (_currentFadeAnimation == animation) _currentFadeAnimation = nil;
	[animation release];
}

- (void)fadeInState:(RXRenderState*)state over:(NSTimeInterval)duration completionDelegate:(id)delegate completionSelector:(SEL)completionSelector {
	RXRenderStateCompositionDescriptor* descriptor = (RXRenderStateCompositionDescriptor*)NSMapGet(_state_map, state);
	if (!descriptor) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"%@ is not composited by this compositor" userInfo:nil];
	
	NSAnimation* animation = [[RXRenderStateOpacityAnimation alloc] initWithState:state targetOpacity:1.0f duration:duration];
	if (!_currentFadeAnimation) _currentFadeAnimation = animation;
	else {
		[animation startWhenAnimation:_currentFadeAnimation reachesProgress:1.0];
		_currentFadeAnimation = animation;
	}
	
	NSMethodSignature* completionSignature = [delegate methodSignatureForSelector:completionSelector];
	NSInvocation* completionInvocation = [NSInvocation invocationWithMethodSignature:completionSignature];
	[completionInvocation setTarget:delegate];
	[completionInvocation setSelector:completionSelector];
	[completionInvocation setArgument:state atIndex:2];
	NSMapInsert(_animationCompletionInvocations, _currentFadeAnimation, completionInvocation);
	
	[_currentFadeAnimation setDelegate:self];
	[_currentFadeAnimation startAnimation];
}

- (void)fadeOutState:(RXRenderState*)state over:(NSTimeInterval)duration completionDelegate:(id)delegate completionSelector:(SEL)completionSelector {
	RXRenderStateCompositionDescriptor* descriptor = (RXRenderStateCompositionDescriptor*)NSMapGet(_state_map, state);
	if (!descriptor) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"%@ is not composited by this compositor" userInfo:nil];
	
	NSAnimation* animation = [[RXRenderStateOpacityAnimation alloc] initWithState:state targetOpacity:0.0f duration:duration];
	if (!_currentFadeAnimation) _currentFadeAnimation = animation;
	else {
		[animation startWhenAnimation:_currentFadeAnimation reachesProgress:1.0];
		_currentFadeAnimation = animation;
	}
	
	NSMethodSignature* completionSignature = [delegate methodSignatureForSelector:completionSelector];
	NSInvocation* completionInvocation = [NSInvocation invocationWithMethodSignature:completionSignature];
	[completionInvocation setTarget:delegate];
	[completionInvocation setSelector:completionSelector];
	[completionInvocation setArgument:state atIndex:2];
	NSMapInsert(_animationCompletionInvocations, _currentFadeAnimation, completionInvocation);
	
	[_currentFadeAnimation setDelegate:self];
	[_currentFadeAnimation startAnimation];
}

#pragma mark -

- (void)stateDidDiffuse:(RXRenderState *)state {
	// FIXME: implement stateDidDiffuse
}

#pragma mark -

- (CGRect)renderRect {
	CGRect rect;
	rect.origin = CGPointZero;
	rx_size_t viewportSize = RXGetGLViewportSize();
	rect.size = CGSizeMake(viewportSize.width, viewportSize.height);
	return rect;
}

- (void)setRenderRect:(CGRect)rect {}

- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx framebuffer:(GLuint)fbo {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	NSArray* renderStates = [_renderStates retain];
	
	// if we have no state, we can exit immediately
	if ([renderStates count] == 0) {
		[renderStates release];
		return;
	}
	
	NSEnumerator* stateEnum = [renderStates objectEnumerator];
	RXRenderStateCompositionDescriptor* descriptor;
	while ((descriptor = [stateEnum nextObject])) {
		// If the state is fully transparent, we can skip rendering altogether
		if (descriptor->opacity == 0.0f) continue;
		
		// bind the render state's framebuffer and clear its color buffers
		glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, descriptor->fbo); glReportError();
		glClear(GL_COLOR_BUFFER_BIT);
		
		// render the render state
		descriptor->render.imp(descriptor->state, descriptor->render.sel, outputTime, cgl_ctx, descriptor->fbo);
	}
	
	// bind the window server FBO
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0); glReportError();
	
#if defined(DEBUG_GL)
	glValidateProgram(_compositing_program); glReportError();
	GLint valid;
	glGetProgramiv(_compositing_program, GL_VALIDATE_STATUS, &valid);
	if (valid != GL_TRUE) RXOLog(@"program not valid: %u", _compositing_program);
#endif
	
	// bind the compositor program and update the render state blend uniform
	glUseProgram(_compositing_program); glReportError();
	glUniform4fv(_texture_blend_weights_uniform, 1, _texture_blend_weights); glReportError();
	
	// bind the compositing vao
	glBindVertexArrayAPPLE(_compositing_vao); glReportError();
	
	// bind render state textures
	uint32_t state_count = [_states count];
	for (uint32_t state_i = 0; state_i < state_count; state_i++) {
		glActiveTexture(GL_TEXTURE0 + state_i); glReportError();
		GLuint texture = ((RXRenderStateCompositionDescriptor*)[_states objectAtIndex:state_i])->texture;
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, texture); glReportError();
	}
	
	// render all states at once!
	glDrawArrays(GL_QUADS, 0, 4); glReportError();
	
	// set the active texture unit to TEXTURE0 (Riven X assumption)
	glActiveTexture(GL_TEXTURE0); glReportError();
	
	// bind program 0 (FF processing)
	glUseProgram(0); glReportError();
	
	// let each render state do "global" rendering, e.g. rendering inside the window server framebuffer
	stateEnum = [renderStates objectEnumerator];
	while ((descriptor = [stateEnum nextObject])) {
		typedef void (*render_global_t)(id, SEL, CGLContextObj);
		render_global_t imp = (render_global_t)[descriptor->state methodForSelector:@selector(_renderInGlobalContext:)];
		imp(descriptor->state, @selector(_renderInGlobalContext:), cgl_ctx);
	}
	
	[renderStates release];
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	NSArray* renderStates = [_renderStates retain];
	NSEnumerator* stateEnum = [renderStates objectEnumerator];
	RXRenderStateCompositionDescriptor* descriptor;
	while ((descriptor = [stateEnum nextObject]))
		descriptor->post_flush.imp(descriptor->state, descriptor->post_flush.sel, outputTime);
	[renderStates release];
}

#pragma mark -

- (void)mouseDown:(NSEvent *)theEvent {
	// do not dispatch events if an animation is running
	if (_currentFadeAnimation)
		return;
	[((RXRenderStateCompositionDescriptor*)[_states lastObject])->state mouseDown:theEvent];
}

- (void)mouseUp:(NSEvent *)theEvent {
	// do not dispatch events if an animation is running
	if (_currentFadeAnimation)
		return;
	[((RXRenderStateCompositionDescriptor*)[_states lastObject])->state mouseUp:theEvent];
}

- (void)mouseMoved:(NSEvent *)theEvent {
	// do not dispatch events if an animation is running
	if (_currentFadeAnimation)
		return;
	[((RXRenderStateCompositionDescriptor*)[_states lastObject])->state mouseMoved:theEvent];
}

- (void)mouseDragged:(NSEvent *)theEvent {
	// do not dispatch events if an animation is running
	if (_currentFadeAnimation)
		return;
	[((RXRenderStateCompositionDescriptor*)[_states lastObject])->state mouseDragged:theEvent];
}

- (void)keyDown:(NSEvent *)theEvent {
	// do not dispatch events if an animation is running
	if (_currentFadeAnimation) return;

#if defined(DEBUG)
	NSString* characters = [theEvent charactersIgnoringModifiers];
	unichar firstCharacter = [characters characterAtIndex:0];
	RXOLog(@"caught keyDown: 0x%x", firstCharacter);
#endif
	[((RXRenderStateCompositionDescriptor*)[_states lastObject])->state keyDown:theEvent];
}

@end
