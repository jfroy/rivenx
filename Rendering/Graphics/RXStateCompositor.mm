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

#import "RXRenderStateOpacityAnimation.h"


@interface RXRenderStateCompositionDescriptor : NSObject {
@public
	RXRenderState* state;
	GLfloat opacity;
	
	rx_render_dispatch_t render;
	rx_post_flush_tasks_dispatch_t post_flush;
	
	GLuint texture;
}
@end

@implementation RXRenderStateCompositionDescriptor

- (void)dealloc {
	[state release];
	[super dealloc];
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime parent:(id)parent {
	// This method only forwards
	[state performPostFlushTasks:outputTime parent:parent];
}

@end


@implementation RXStateCompositor

- (id)init {
	self = [super init];
	if (!self) return nil;
	
	_states = [[NSMutableArray alloc] initWithCapacity:0x10];
	_state_map = NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks, NSNonRetainedObjectMapValueCallBacks, 0);
	_animationCompletionInvocations = NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks, NSObjectMapValueCallBacks, 0);
	
	_renderStates = [_states copy];
	
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	CGLLockContext(cgl_ctx);
	
	// we use one FBO to render the states to textures, which we then composite to the window server framebuffer
	glGenFramebuffersEXT(1, &_fbo);
	
	// render state composition shader
	NSString* vshader_source = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"state_compositor" ofType:@"vs" inDirectory:@"Shaders"] encoding:NSASCIIStringEncoding error:NULL];
	NSString* fshader_source = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"state_compositor" ofType:@"fs" inDirectory:@"Shaders"] encoding:NSASCIIStringEncoding error:NULL];
	
	_compositor_program = glCreateProgram(); glReportError();
	
	GLuint vshader = glCreateShader(GL_VERTEX_SHADER); glReportError();
	GLuint fshader = glCreateShader(GL_FRAGMENT_SHADER); glReportError();
	
	const GLcharARB* shader_source_cstring = [vshader_source cStringUsingEncoding:NSASCIIStringEncoding];
	if (!shader_source_cstring) {
		[self release];
		return nil;
	}
	glShaderSource(vshader, 1, &shader_source_cstring, NULL); glReportError();
	
	shader_source_cstring = [fshader_source cStringUsingEncoding:NSASCIIStringEncoding];
	if (!shader_source_cstring) {
		[self release];
		return nil;
	}
	glShaderSource(fshader, 1, &shader_source_cstring, NULL); glReportError();
	
	glCompileShader(vshader); glReportError();
#if defined(DEBUG)
	GLint status;
	glGetShaderiv(vshader, GL_COMPILE_STATUS, &status);
	if (status != GL_TRUE) RXOLog(@"failed to compile shader: state_compositor.vs\n%@", vshader_source);
#endif
	glCompileShader(fshader); glReportError();
#if defined(DEBUG)
	glGetShaderiv(fshader, GL_COMPILE_STATUS, &status);
	if (status != GL_TRUE) RXOLog(@"failed to compile shader: state_compositor.fs\n%@", fshader_source);
#endif
	
	glAttachShader(_compositor_program, vshader); glReportError();
	glAttachShader(_compositor_program, fshader); glReportError();
	glLinkProgram(_compositor_program); glReportError();
#if defined(DEBUG)
	glGetProgramiv(_compositor_program, GL_LINK_STATUS, &status);
	if (status != GL_TRUE) RXOLog(@"failed to link program");
#endif
	
	_texture_units_uniform = glGetUniformLocation(_compositor_program, "texture_units"); glReportError();
	_texture_blend_weights_uniform = glGetUniformLocation(_compositor_program, "texture_blend_weights"); glReportError();
	
	glUseProgram(_compositor_program); glReportError();
	
	GLint samplers[4] = {0, 1, 2, 3};
	glUniform1iv(_texture_units_uniform, 4, samplers); glReportError();
	glUniform4f(_texture_blend_weights_uniform, 0.0f, 0.0f, 0.0f, 0.0f); glReportError();
	
	glUseProgram(0);
	
	glDeleteShader(vshader); glReportError();
	glDeleteShader(fshader); glReportError();
	
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
	
	[_states removeAllObjects];
	NSResetMapTable(_state_map);
	
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	CGLLockContext(cgl_ctx);
	{
		glDeleteFramebuffersEXT(1, &_fbo);
		glDeleteProgram(_compositor_program);
	}
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
	
	// re-enable client storage
	glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
	
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

- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx parent:(id)parent {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	NSArray* renderStates = [_renderStates retain];
	
	// if we have no state, we can exit immediately
	if ([renderStates count] == 0) {
		[renderStates release];
		return;
	}
	
	// bind the state render FBO
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _fbo);
	
	NSEnumerator* stateEnum = [renderStates objectEnumerator];
	RXRenderStateCompositionDescriptor* descriptor;
	while ((descriptor = [stateEnum nextObject])) {
		// If the state is fully transparent, we can skip rendering altogether
		if (descriptor->opacity == 0.0f) continue;
		
		// color0 texture attach
		glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_ARB, descriptor->texture, 0);
		glReportError();
		
		// completeness check
#if defined(DEBUG)
		GLenum status = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
		if (status != GL_FRAMEBUFFER_COMPLETE_EXT) {
			RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"FBO not complete, status 0x%04x\n", (unsigned int)status);
			continue;
		}
#endif
		
		glClear(GL_COLOR_BUFFER_BIT);
		descriptor->render.imp(descriptor->state, descriptor->render.sel, outputTime, cgl_ctx, self);
	}
	
	// bind the window server FBO
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0); glReportError();
	
#if defined(DEBUG)
	glValidateProgram(_compositor_program);
	GLint valid;
	glGetProgramiv(_compositor_program, GL_VALIDATE_STATUS, &valid);
	if (valid != GL_TRUE) RXOLog(@"program not valid: %u", _compositor_program);
#endif
	
	// configure what we need
	glUseProgram(_compositor_program); glReportError();
	glUniform4fv(_texture_blend_weights_uniform, 1, _texture_blend_weights); glReportError();
	
	glVertexPointer(2, GL_FLOAT, 0, vertex_coords); glReportError();
	
	// setup render state textures
	uint32_t state_count = [_states count];
	for (uint32_t state_i = 0; state_i < state_count; state_i++) {
		glActiveTexture(GL_TEXTURE0 + state_i); glReportError();
		glTexCoordPointer(2, GL_FLOAT, 0, tex_coords); glReportError();
		GLuint texture = ((RXRenderStateCompositionDescriptor*)[_states objectAtIndex:state_i])->texture;
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, texture);
	}
	
	// render all states at once!
	glDrawArrays(GL_QUADS, 0, 4); glReportError();
	
	// bind program 0 again
	glUseProgram(0); glReportError();
	
	stateEnum = [renderStates objectEnumerator];
	while ((descriptor = [stateEnum nextObject])) {
		typedef void (*render_global_t)(id, SEL, CGLContextObj);
		render_global_t imp = (render_global_t)[descriptor->state methodForSelector:@selector(_renderInGlobalContext:)];
		imp(descriptor->state, @selector(_renderInGlobalContext:), cgl_ctx);
	}
	
	[renderStates release];
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime parent:(id)parent {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	NSArray* renderStates = [_renderStates retain];
	NSEnumerator* stateEnum = [renderStates objectEnumerator];
	RXRenderStateCompositionDescriptor* descriptor;
	while ((descriptor = [stateEnum nextObject])) descriptor->post_flush.imp(descriptor->state, descriptor->post_flush.sel, outputTime, self);
	[renderStates release];
}

#pragma mark -

- (void)mouseDown:(NSEvent *)theEvent {
	// do not dispatch events if an animation is running
	if (_currentFadeAnimation) return;
	
	[((RXRenderStateCompositionDescriptor*)[_states lastObject])->state mouseDown:theEvent];
}

- (void)mouseUp:(NSEvent *)theEvent {
	// do not dispatch events if an animation is running
	if (_currentFadeAnimation) return;
	
	[((RXRenderStateCompositionDescriptor*)[_states lastObject])->state mouseUp:theEvent];
}

- (void)mouseMoved:(NSEvent *)theEvent {
	// do not dispatch events if an animation is running
	if (_currentFadeAnimation) return;
	
	[((RXRenderStateCompositionDescriptor*)[_states lastObject])->state mouseMoved:theEvent];
}

- (void)mouseDragged:(NSEvent *)theEvent {
	// do not dispatch events if an animation is running
	if (_currentFadeAnimation) return;
	
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
