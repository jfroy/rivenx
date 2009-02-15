//
//	RXCardState.m
//	rivenx
//
//	Created by Jean-Francois Roy on 24/01/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import <OpenGL/CGLMacro.h>

#import <GLUT/GLUT.h>

#import <mach/mach.h>
#import <mach/mach_time.h>

#import <MHKKit/MHKAudioDecompression.h>

#import "Base/RXTiming.h"
#import "Engine/RXWorldProtocol.h"

#import "States/RXCardState.h"

#import "Engine/RXHardwareProfiler.h"
#import "Engine/RXHotspot.h"
#import "Engine/RXEditionManager.h"

#import "Rendering/Audio/RXCardAudioSource.h"
#import "Rendering/Graphics/GL/GLShaderProgramManager.h"
#import "Rendering/Graphics/RXMovieProxy.h"

typedef void (*RenderCardImp_t)(id, SEL, const CVTimeStamp*, CGLContextObj);
static RenderCardImp_t render_card_imp;
static SEL render_card_sel = @selector(_renderCardWithTimestamp:inContext:);

typedef void (*PostFlushCardImp_t)(id, SEL, const CVTimeStamp*);
static PostFlushCardImp_t post_flush_card_imp;
static SEL post_flush_card_sel = @selector(_postFlushCard:);

static rx_render_dispatch_t picture_render_dispatch;
static rx_post_flush_tasks_dispatch_t picture_flush_task_dispatch;

static rx_render_dispatch_t _movieRenderDispatch;
static rx_post_flush_tasks_dispatch_t _movieFlushTasksDispatch;

static const double RX_AUDIO_RAMP_DURATION = 2.0;
static const double RX_AUDIO_RAMP_DURATION__PLUS_POINT_FIVE = RX_AUDIO_RAMP_DURATION + 0.5;

static const GLuint RX_CARD_DYNAMIC_RENDER_INDEX = 0;

static const GLuint RX_MAX_RENDER_HOTSPOT = 20;

static const GLuint RX_MAX_INVENTORY_ITEMS = 3;
static const NSString* RX_INVENTORY_KEYS[3] = {
	@"Atrus",
	@"Catherine",
	@"Prison"
};
static const int RX_INVENTORY_ATRUS = 0;
static const int RX_INVENTORY_CATHERINE = 1;
static const int RX_INVENTORY_PRISON = 2;
static const float RX_INVENTORY_MARGIN = 20.f;

#pragma mark -
#pragma mark audio source array callbacks

static const void* RXCardAudioSourceArrayWeakRetain(CFAllocatorRef allocator, const void* value) {
	return value;
}

static void RXCardAudioSourceArrayWeakRelease(CFAllocatorRef allocator, const void* value) {

}

static void RXCardAudioSourceArrayDeleteRelease(CFAllocatorRef allocator, const void* value) {
	delete const_cast<RX::CardAudioSource*>(reinterpret_cast<const RX::CardAudioSource*>(value));
}

static CFStringRef RXCardAudioSourceArrayDescription(const void* value) {
	return CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::CardAudioSource: 0x%x>"), value);
}

static Boolean RXCardAudioSourceArrayEqual(const void* value1, const void* value2) {
	return value1 == value2;
}

static CFArrayCallBacks g_weakAudioSourceArrayCallbacks = {0, RXCardAudioSourceArrayWeakRetain, RXCardAudioSourceArrayWeakRelease, RXCardAudioSourceArrayDescription, RXCardAudioSourceArrayEqual};
static CFArrayCallBacks g_deleteOnReleaseAudioSourceArrayCallbacks = {0, RXCardAudioSourceArrayWeakRetain, RXCardAudioSourceArrayDeleteRelease, RXCardAudioSourceArrayDescription, RXCardAudioSourceArrayEqual};

#pragma mark -
#pragma mark audio array applier functions

static void RXCardAudioSourceFadeInApplier(const void* value, void* context) {
	RX::AudioRenderer* renderer = reinterpret_cast<RX::AudioRenderer*>(context);
	RX::CardAudioSource* source = const_cast<RX::CardAudioSource*>(reinterpret_cast<const RX::CardAudioSource*>(value));
	renderer->SetSourceGain(*source, 0.0f);
	renderer->RampSourceGain(*source, source->NominalGain(), RX_AUDIO_RAMP_DURATION);
}

static void RXCardAudioSourceEnableApplier(const void* value, void* context) {
	RX::CardAudioSource* source = const_cast<RX::CardAudioSource*>(reinterpret_cast<const RX::CardAudioSource*>(value));
	source->SetEnabled(true);
}

static void RXCardAudioSourceDisableApplier(const void* value, void* context) {
	RX::CardAudioSource* source = const_cast<RX::CardAudioSource*>(reinterpret_cast<const RX::CardAudioSource*>(value));
	source->SetEnabled(false);
}

static void RXCardAudioSourceTaskApplier(const void* value, void* context) {
	RX::CardAudioSource* source = const_cast<RX::CardAudioSource*>(reinterpret_cast<const RX::CardAudioSource*>(value));
	source->RenderTask();
}

#pragma mark -
#pragma mark render object release-owner array applier function

static void rx_release_owner_applier(const void* value, void* context) {
	[[(id)value owner] release];
}

//static void rx_retain_owner_applier(const void* value, void* context) {
//	[[(id)value owner] retain];
//}

#pragma mark -

@interface RXCardState (RXCardStatePrivate)
- (void)_initializeRendering;
- (void)_updateActiveSources;
@end

@implementation RXCardState

+ (void)initialize {
	static BOOL initialized = NO;
	if (!initialized) {
		initialized = YES;
		
		render_card_imp = (RenderCardImp_t)[self instanceMethodForSelector:render_card_sel];
		post_flush_card_imp = (PostFlushCardImp_t)[self instanceMethodForSelector:post_flush_card_sel];
		
		picture_render_dispatch = RXGetRenderImplementation([RXPicture class], RXRenderingRenderSelector);
		picture_flush_task_dispatch = RXGetPostFlushTasksImplementation([RXPicture class], RXRenderingPostFlushTasksSelector);
		
		_movieRenderDispatch = RXGetRenderImplementation([RXMovieProxy class], RXRenderingRenderSelector);
		_movieFlushTasksDispatch = RXGetPostFlushTasksImplementation([RXMovieProxy class], RXRenderingPostFlushTasksSelector);
	}
}

- (id)init {
	self = [super init];
	if (!self)
		return nil;
	
	sengine = [[RXScriptEngine alloc] initWithController:self];
	
	// get the cache line size
	size_t cache_line_size = [[RXHardwareProfiler sharedHardwareProfiler] cacheLineSize];
	
	// allocate enough cache lines to store 2 render states without overlap (to avoid false sharing)
	uint32_t render_state_cache_line_count = sizeof(struct rx_card_state_render_state) / cache_line_size;
	if (sizeof(struct rx_card_state_render_state) % cache_line_size)
		render_state_cache_line_count++;
	
	// allocate the cache lines
	_render_states_buffer = malloc((render_state_cache_line_count * 2 + 1) * cache_line_size);
	
	// point each render state pointer at the beginning of a cache line
	_front_render_state = (struct rx_card_state_render_state*)BUFFER_OFFSET(((uintptr_t)_render_states_buffer & ~(cache_line_size - 1)), cache_line_size);
	_back_render_state = (struct rx_card_state_render_state*)BUFFER_OFFSET(((uintptr_t)_front_render_state & ~(cache_line_size - 1)), cache_line_size);
	
	// zero-fill the render states to be extra-safe
	bzero((void*)_front_render_state, sizeof(struct rx_card_state_render_state));
	bzero((void*)_back_render_state, sizeof(struct rx_card_state_render_state));
	
	// allocate the arrays embedded in the render states
	_front_render_state->pictures = [NSMutableArray new];
	_back_render_state->pictures = [NSMutableArray new];
	
	_active_movies = [NSMutableArray new];
	_activeSounds = [NSMutableSet new];
	_activeDataSounds = [NSMutableSet new];
	_activeSources = CFArrayCreateMutable(NULL, 0, &g_weakAudioSourceArrayCallbacks);
	
	_transitionQueue = [NSMutableArray new];
	
	kern_return_t kerr;
	kerr = semaphore_create(mach_task_self(), &_audioTaskThreadExitSemaphore, SYNC_POLICY_FIFO, 0);
	if (kerr != 0)
		goto init_failure;
	
	kerr = semaphore_create(mach_task_self(), &_transitionSemaphore, SYNC_POLICY_FIFO, 0);
	if (kerr != 0)
		goto init_failure;
	
	_renderLock = OS_SPINLOCK_INIT;
	_state_swap_lock = OS_SPINLOCK_INIT;
	
	// initialize all the rendering stuff (shaders, textures, buffers, VAOs)
	[self _initializeRendering];
	
	// initialize the mouse vector
	_mouseVector.origin = [(NSView*)g_worldView convertPoint:[[(NSView*)g_worldView window] mouseLocationOutsideOfEventStream] fromView:nil];
	_mouseVector.size.width = INFINITY;
	_mouseVector.size.height = INFINITY;
	
	// register for current card request notifications
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_broadcastCurrentCard:) name:@"RXBroadcastCurrentCardNotification" object:nil];
	
	// register for window key notifications to update the hotspot state
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleWindowDidBecomeKey:) name:NSWindowDidBecomeKeyNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleWindowDidResignKey:) name:NSWindowDidResignKeyNotification object:nil];
	
	return self;
	
init_failure:
	[self release];
	return nil;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	if (_transitionSemaphore)
		semaphore_destroy(mach_task_self(), _transitionSemaphore);
	if (_audioTaskThreadExitSemaphore)
		semaphore_destroy(mach_task_self(), _audioTaskThreadExitSemaphore);
	
	[_transitionQueue release];
	
	CFRelease(_activeSources);
	[_activeDataSounds release];
	[_activeSounds release];
	[_active_movies release];
	
	if (_render_states_buffer) {
		[_front_render_state->pictures release];
		[_back_render_state->pictures release];
		
		free(_render_states_buffer);
	}
	
	[sengine release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark rendering initialization

- (void)_reportShaderProgramError:(NSError*)error {
	if ([[error domain] isEqualToString:GLShaderCompileErrorDomain])
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"%@ shader failed to compile:\n%@\n%@", [[error userInfo] objectForKey:@"GLShaderType"], [[error userInfo] objectForKey:@"GLCompileLog"], [[error userInfo] objectForKey:@"GLShaderSource"]);
	else if ([[error domain] isEqualToString:GLShaderLinkErrorDomain])
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"%@ shader program failed to link:\n%@", [[error userInfo] objectForKey:@"GLLinkLog"]);
	else
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"failed to create shader program: %@", error);
}

- (struct rx_transition_program)_loadTransitionShaderWithName:(NSString*)name direction:(RXTransitionDirection)direction context:(CGLContextObj)cgl_ctx {
	NSError* error;
	
	struct rx_transition_program program;
	GLint sourceTextureUniform;
	GLint destinationTextureUniform;
	
	NSString* directionSource = [NSString stringWithFormat:@"#define RX_DIRECTION %d\n", direction];
	NSArray* extraSource = [NSArray arrayWithObjects:@"#version 110\n", directionSource, nil];
	
	program.program = [[GLShaderProgramManager sharedManager] standardProgramWithFragmentShaderName:name extraSources:extraSource epilogueIndex:[extraSource count] context:cgl_ctx error:&error];
	if (program.program == 0) {
		[self _reportShaderProgramError:error];
		return program;
	}
	
	sourceTextureUniform = glGetUniformLocation(program.program, "source"); glReportError();
	destinationTextureUniform = glGetUniformLocation(program.program, "destination"); glReportError();
	
	program.margin_uniform = glGetUniformLocation(program.program, "margin"); glReportError();
	program.t_uniform = glGetUniformLocation(program.program, "t"); glReportError();
	program.card_size_uniform = glGetUniformLocation(program.program, "cardSize"); glReportError();
	
	glUseProgram(program.program); glReportError();
	glUniform1i(sourceTextureUniform, 1); glReportError();
	glUniform1i(destinationTextureUniform, 0); glReportError();
	
	if (program.card_size_uniform != -1)
		glUniform2f(program.card_size_uniform, kRXCardViewportSize.width, kRXCardViewportSize.height);
	
	if (program.margin_uniform != -1)
		glUniform2f(program.margin_uniform, kRXCardViewportOriginOffset.x, kRXCardViewportOriginOffset.y);
	
	glReportError();
	return program;
}

- (void)_initializeRendering {
	// WARNING: WILL BE RUNNING ON THE MAIN THREAD
	NSError* error;
	
	// use the load context to prepare our GL objects
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	CGLLockContext(cgl_ctx);
	NSObject<RXOpenGLStateProtocol>* gl_state = g_loadContextState;
	
	// kick start the audio task thread
	[NSThread detachNewThreadSelector:@selector(_audioTaskThread:) toTarget:self withObject:nil];
	
	// we need one FBO to render a card's composite texture and one FBO to apply the water effect; as well as matching textures for the color0 attachement point and one extra texture to store the previous frame
	glGenFramebuffersEXT(1, _fbos);
	glGenTextures(1, _textures);
	
	// disable client storage because it's incompatible with allocating texture space with NULL (which is what we want to do for FBO color attachement textures) and with the PIXEL_UNPACK buffer
	glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_FALSE);
	
	for (GLuint i = 0; i < 1; i++) {
		glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _fbos[i]); glReportError();
		
		// bind the texture
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _textures[i]); glReportError();
		
		// texture parameters
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glReportError();
		
		// allocate memory for the texture
		glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, kRXRendererViewportSize.width, kRXRendererViewportSize.height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL); glReportError();
		
		// color0 texture attach
		glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_ARB, _textures[i], 0); glReportError();
		
		// completeness check
		GLenum fboStatus = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
		if (fboStatus != GL_FRAMEBUFFER_COMPLETE_EXT)
			RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"FBO not complete, status 0x%04x\n", (unsigned int)fboStatus);
	}
	
	// create the water unpack buffer and the water readback buffer
	glGenBuffers(1, &_water_buffer); glReportError();
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, _water_buffer); glReportError();
	glBufferData(GL_PIXEL_UNPACK_BUFFER, (kRXRendererViewportSize.width * kRXRendererViewportSize.height) << 2, NULL, GL_DYNAMIC_DRAW); glReportError();
	_water_readback_buffer = malloc((kRXRendererViewportSize.width * kRXRendererViewportSize.height) << 2);
	
	// get a reference to the extra bitmaps archive, and get the inventory texture descriptors
	MHKArchive* extraBitmapsArchive = [g_world extraBitmapsArchive];
	NSDictionary* journalDescriptors = [[g_world extraBitmapsDescriptor] objectForKey:@"Journals"];
	
	// get the texture descriptors for the inventory textures and compute the total byte size of those textures (packed BGRA format)
	// FIXME: we need actual error handling beyond just logging...
	NSDictionary* inventoryTextureDescriptors[3];
	uint32_t inventoryTotalTextureSize = 0;
	for (GLuint inventory_i = 0; inventory_i < RX_MAX_INVENTORY_ITEMS; inventory_i++) {
		inventoryTextureDescriptors[inventory_i] = [[g_world extraBitmapsArchive] bitmapDescriptorWithID:[[journalDescriptors objectForKey:RX_INVENTORY_KEYS[inventory_i]] unsignedShortValue] error:&error];
		if (!inventoryTextureDescriptors[inventory_i]) {
			RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"failed to get inventory texture descriptor for item \"%@\": %@", RX_INVENTORY_KEYS[inventory_i], error);
			continue;
		}
		
		// cache the dimensions of the inventory item textures in the inventory regions
		_inventoryRegions[inventory_i].size.width = [[inventoryTextureDescriptors[inventory_i] objectForKey:@"Width"] floatValue];
		_inventoryRegions[inventory_i].size.height = [[inventoryTextureDescriptors[inventory_i] objectForKey:@"Height"] floatValue];
		
		inventoryTotalTextureSize += (uint32_t)(_inventoryRegions[inventory_i].size.width * _inventoryRegions[inventory_i].size.height) << 2;
	}
	
	// load the journal inventory textures in an unpack buffer object
	GLuint inventory_unpack_buffer;
	glGenBuffers(1, &inventory_unpack_buffer); glReportError();
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, inventory_unpack_buffer); glReportError();
	
	// allocate the texture buffer (aligned to 128 bytes)
	inventoryTotalTextureSize = (inventoryTotalTextureSize & ~0x7f) + 0x80;
	glBufferData(GL_PIXEL_UNPACK_BUFFER, inventoryTotalTextureSize, NULL, GL_STATIC_DRAW); glReportError();
	
	// map the buffer in
	void* inventoryBuffer = glMapBuffer(GL_PIXEL_UNPACK_BUFFER, GL_WRITE_ONLY); glReportError();
	
	// decompress the textures into the buffer
	// FIXME: we need actual error handling beyond just logging...
	for (GLuint inventory_i = 0; inventory_i < RX_MAX_INVENTORY_ITEMS; inventory_i++) {
		if (![extraBitmapsArchive loadBitmapWithID:[[journalDescriptors objectForKey:RX_INVENTORY_KEYS[inventory_i]] unsignedShortValue] buffer:inventoryBuffer format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED error:&error]) {
			RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"failed to load inventory texture for item \"%@\": %@", RX_INVENTORY_KEYS[inventory_i], error);
			continue;
		}
		
		inventoryBuffer = BUFFER_OFFSET(inventoryBuffer, (uint32_t)(_inventoryRegions[inventory_i].size.width * _inventoryRegions[inventory_i].size.height) << 2);
	}
	
	// unmap the pixel unpack buffer to begin the DMA transfer
	glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER); glReportError();
	
	// while we DMA the inventory textures, let's do some more work
	
	// card composite VAO / VA / VBO
	
	// gen the buffers
	glGenVertexArraysAPPLE(1, &_cardCompositeVAO); glReportError();
	glGenBuffers(1, &_cardCompositeVBO); glReportError();
	
	// bind them
	[gl_state bindVertexArrayObject:_cardCompositeVAO];
	glBindBuffer(GL_ARRAY_BUFFER, _cardCompositeVBO); glReportError();
	
	// enable sub-range flushing if available
	if (GLEE_APPLE_flush_buffer_range)
		glBufferParameteriAPPLE(GL_ARRAY_BUFFER, GL_BUFFER_FLUSHING_UNMAP_APPLE, GL_FALSE);
	
	// 4 triangle strip primitives, 4 vertices per strip, [<position.x position.y> <texcoord0.s texcoord0.t>], floats
	glBufferData(GL_ARRAY_BUFFER, 64 * sizeof(GLfloat), NULL, GL_STREAM_DRAW); glReportError();
	
	// map the VBO and write the vertex attributes
	GLfloat* positions = reinterpret_cast<GLfloat*>(glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY)); glReportError();
	GLfloat* tex_coords0 = positions + 2;
	
	// main card composite
	{
		positions[0] = kRXCardViewportOriginOffset.x; positions[1] = kRXCardViewportOriginOffset.y + kRXCardViewportSize.height;
		tex_coords0[0] = 0.0f; tex_coords0[1] = 0.0f;
		positions += 4; tex_coords0 += 4;
		
		positions[0] = kRXCardViewportOriginOffset.x + kRXCardViewportSize.width; positions[1] = kRXCardViewportOriginOffset.y + kRXCardViewportSize.height;
		tex_coords0[0] = kRXCardViewportSize.width; tex_coords0[1] = 0.0f;
		positions += 4; tex_coords0 += 4;
		
		positions[0] = kRXCardViewportOriginOffset.x; positions[1] = kRXCardViewportOriginOffset.y;
		tex_coords0[0] = 0.0f; tex_coords0[1] = kRXCardViewportSize.height;
		positions += 4; tex_coords0 += 4;
		
		positions[0] = kRXCardViewportOriginOffset.x + kRXCardViewportSize.width; positions[1] = kRXCardViewportOriginOffset.y;
		tex_coords0[0] = kRXCardViewportSize.width; tex_coords0[1] = kRXCardViewportSize.height;
		positions += 4; tex_coords0 += 4;
	}
		
	// unmap and flush the card composite VBO
	if (GLEE_APPLE_flush_buffer_range)
		glFlushMappedBufferRangeAPPLE(GL_ARRAY_BUFFER, 0, 16 * sizeof(GLfloat));
	glUnmapBuffer(GL_ARRAY_BUFFER); glReportError();
	
	// configure the VAs
	glEnableClientState(GL_VERTEX_ARRAY); glReportError();
	glVertexPointer(2, GL_FLOAT, 4 * sizeof(GLfloat), BUFFER_OFFSET(NULL, 0)); glReportError();
	
	glClientActiveTexture(GL_TEXTURE0);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
	glTexCoordPointer(2, GL_FLOAT, 4 * sizeof(GLfloat), (void*)BUFFER_OFFSET(NULL, 2 * sizeof(GLfloat))); glReportError();
	
	// shaders
	
	// water animation shader
	_waterProgram = [[GLShaderProgramManager sharedManager] standardProgramWithFragmentShaderName:@"water" extraSources:nil epilogueIndex:0 context:cgl_ctx error:&error];
	if (!_waterProgram)
		[self _reportShaderProgramError:error];
	
	GLint cardTextureUniform = glGetUniformLocation(_waterProgram, "card_texture"); glReportError();
	GLint displacementMapUniform = glGetUniformLocation(_waterProgram, "water_displacement_map"); glReportError();
	GLint previousFrameUniform = glGetUniformLocation(_waterProgram, "previous_frame"); glReportError();
	
	glUseProgram(_waterProgram); glReportError();
	glUniform1i(cardTextureUniform, 0); glReportError();
	glUniform1i(displacementMapUniform, 1); glReportError();
	glUniform1i(previousFrameUniform, 2); glReportError();
	
	// card shader
	_single_rect_texture_program = [[GLShaderProgramManager sharedManager] standardProgramWithFragmentShaderName:@"card" extraSources:nil epilogueIndex:0 context:cgl_ctx error:&error];
	if (!_single_rect_texture_program)
		[self _reportShaderProgramError:error];
	
	GLint destinationCardTextureUniform = glGetUniformLocation(_single_rect_texture_program, "destination_card"); glReportError();
	glUseProgram(_single_rect_texture_program); glReportError();
	glUniform1i(destinationCardTextureUniform, 0); glReportError();
	
	// transition shaders
	_dissolve = [self _loadTransitionShaderWithName:@"transition_crossfade" direction:0 context:cgl_ctx];
	
	_push[RXTransitionLeft] = [self _loadTransitionShaderWithName:@"transition_push" direction:RXTransitionLeft context:cgl_ctx];
	_push[RXTransitionRight] = [self _loadTransitionShaderWithName:@"transition_push" direction:RXTransitionRight context:cgl_ctx];
	_push[RXTransitionTop] = [self _loadTransitionShaderWithName:@"transition_push" direction:RXTransitionTop context:cgl_ctx];
	_push[RXTransitionBottom] = [self _loadTransitionShaderWithName:@"transition_push" direction:RXTransitionBottom context:cgl_ctx];
	
	_slide_out[RXTransitionLeft] = [self _loadTransitionShaderWithName:@"transition_slide_out" direction:RXTransitionLeft context:cgl_ctx];
	_slide_out[RXTransitionRight] = [self _loadTransitionShaderWithName:@"transition_slide_out" direction:RXTransitionRight context:cgl_ctx];
	_slide_out[RXTransitionTop] = [self _loadTransitionShaderWithName:@"transition_slide_out" direction:RXTransitionTop context:cgl_ctx];
	_slide_out[RXTransitionBottom] = [self _loadTransitionShaderWithName:@"transition_slide_out" direction:RXTransitionBottom context:cgl_ctx];
	
	_slide_in[RXTransitionLeft] = [self _loadTransitionShaderWithName:@"transition_slide_in" direction:RXTransitionLeft context:cgl_ctx];
	_slide_in[RXTransitionRight] = [self _loadTransitionShaderWithName:@"transition_slide_in" direction:RXTransitionRight context:cgl_ctx];
	_slide_in[RXTransitionTop] = [self _loadTransitionShaderWithName:@"transition_slide_in" direction:RXTransitionTop context:cgl_ctx];
	_slide_in[RXTransitionBottom] = [self _loadTransitionShaderWithName:@"transition_slide_in" direction:RXTransitionBottom context:cgl_ctx];
	
	_swipe[RXTransitionLeft] = [self _loadTransitionShaderWithName:@"transition_swipe" direction:RXTransitionLeft context:cgl_ctx];
	_swipe[RXTransitionRight] = [self _loadTransitionShaderWithName:@"transition_swipe" direction:RXTransitionRight context:cgl_ctx];
	_swipe[RXTransitionTop] = [self _loadTransitionShaderWithName:@"transition_swipe" direction:RXTransitionTop context:cgl_ctx];
	_swipe[RXTransitionBottom] = [self _loadTransitionShaderWithName:@"transition_swipe" direction:RXTransitionBottom context:cgl_ctx];
	
	// create a VAO and VBO for hotspot debug rendering
	glGenVertexArraysAPPLE(1, &_hotspotDebugRenderVAO); glReportError();
	glGenBuffers(1, &_hotspotDebugRenderVBO); glReportError();
	
	// bind them
	[gl_state bindVertexArrayObject:_hotspotDebugRenderVAO];
	glBindBuffer(GL_ARRAY_BUFFER, _hotspotDebugRenderVBO); glReportError();
	
	// enable sub-range flushing if available
	if (GLEE_APPLE_flush_buffer_range)
		glBufferParameteriAPPLE(GL_ARRAY_BUFFER, GL_BUFFER_FLUSHING_UNMAP_APPLE, GL_FALSE);
	
	// 4 lines per hotspot, 6 floats per line (coord[x, y] color[r, g, b, a])
	glBufferData(GL_ARRAY_BUFFER, (RX_MAX_RENDER_HOTSPOT + RX_MAX_INVENTORY_ITEMS) * 24 * sizeof(GLfloat), NULL, GL_STREAM_DRAW); glReportError();
	
	// configure the VAs
	glEnableClientState(GL_VERTEX_ARRAY); glReportError();
	glVertexPointer(2, GL_FLOAT, 6 * sizeof(GLfloat), NULL); glReportError();
	
	glEnableClientState(GL_COLOR_ARRAY); glReportError();
	glColorPointer(4, GL_FLOAT, 6 * sizeof(GLfloat), (void*)BUFFER_OFFSET(NULL, 2 * sizeof(GLfloat))); glReportError();
	
	// allocate the first element and element count arrays
	_hotspotDebugRenderFirstElementArray = new GLint[RX_MAX_RENDER_HOTSPOT + RX_MAX_INVENTORY_ITEMS];
	_hotspotDebugRenderElementCountArray = new GLint[RX_MAX_RENDER_HOTSPOT + RX_MAX_INVENTORY_ITEMS];
	
	// alright, we've done all the work we could, let's now make those inventory textures
	
	// create the textures and reset inventoryBuffer which we'll use as a buffer offset
	glGenTextures(RX_MAX_INVENTORY_ITEMS, _inventoryTextures);
	inventoryBuffer = 0;
	
	// decompress the textures into the buffer
	// FIXME: we need actual error handling beyond just logging...
	for (GLuint inventory_i = 0; inventory_i < RX_MAX_INVENTORY_ITEMS; inventory_i++) {
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _inventoryTextures[inventory_i]); glReportError();
		
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glReportError();
		
		glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, (GLsizei)_inventoryRegions[inventory_i].size.width, (GLsizei)_inventoryRegions[inventory_i].size.height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, inventoryBuffer); glReportError();
		
		inventoryBuffer = BUFFER_OFFSET(inventoryBuffer, (uint32_t)(_inventoryRegions[inventory_i].size.width * _inventoryRegions[inventory_i].size.height) << 2);
	}
	
	// the inventory begins at half opacity
	_inventoryAlphaFactor = 0.5f;
	
	// bind 0 to the unpack buffer (e.g. client memory unpacking)
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
	
	// we're done with the inventory unpack buffer
	glDeleteBuffers(1, &inventory_unpack_buffer);
	
	// re-enable client storage
	glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE); glReportError();
	
	// bind 0 to the current VAO
	[gl_state bindVertexArrayObject:0];
	
	// bind program 0 (e.g. back to fixed-function)
	glUseProgram(0);
	
	// new texture, buffer and program objects
	glFlush();
	
	// done with OpenGL
	CGLUnlockContext(cgl_ctx);
}

#pragma mark -
#pragma mark audio rendering

- (CFMutableArrayRef)_createSourceArrayFromSoundSets:(NSArray*)sets callbacks:(CFArrayCallBacks*)callbacks {
	// create an array of sources that need to be deactivated
	CFMutableArrayRef sources = CFArrayCreateMutable(NULL, 0, callbacks);
	
	NSEnumerator* setEnum = [sets objectEnumerator];
	NSSet* s;
	while ((s = [setEnum nextObject])) {	
		NSEnumerator* soundEnum = [s objectEnumerator];
		RXSound* sound;
		while ((sound = [soundEnum nextObject])) {
			assert(sound->source);
			CFArrayAppendValue(sources, sound->source);
		}
	}
	return sources;
}

- (CFMutableArrayRef)_createSourceArrayFromSoundSet:(NSSet*)s callbacks:(CFArrayCallBacks*)callbacks {
	return [self _createSourceArrayFromSoundSets:[NSArray arrayWithObject:s] callbacks:callbacks];
}

- (void)_updateActiveSources {
	// WARNING: WILL BE RUNNING ON THE SCRIPT THREAD
	NSMutableSet* soundsToRemove = [NSMutableSet new];
	uint64_t now = RXTimingNow();
	
	// find expired sounds, removing associated decompressors and sources as we go
	RXSound* sound;
	
	NSEnumerator* soundEnum = [_activeSounds objectEnumerator];
	while ((sound = [soundEnum nextObject]))
		if (sound->detachTimestampValid && RXTimingTimestampDelta(now, sound->rampStartTimestamp) >= RX_AUDIO_RAMP_DURATION__PLUS_POINT_FIVE)
			[soundsToRemove addObject:sound];
	
	soundEnum = [_activeDataSounds objectEnumerator];
	while ((sound = [soundEnum nextObject]))
		if (sound->detachTimestampValid && RXTimingTimestampDelta(now, sound->rampStartTimestamp) >= sound->source->Duration() + 0.5)
			[soundsToRemove addObject:sound];
	
	// remove expired sounds from the set of active sounds
	[_activeSounds minusSet:soundsToRemove];
	[_activeDataSounds minusSet:soundsToRemove];
	
	// swap the active sources array
	CFMutableArrayRef newActiveSources = [self _createSourceArrayFromSoundSets:[NSArray arrayWithObjects:_activeSounds, _activeDataSounds, nil] callbacks:&g_weakAudioSourceArrayCallbacks];
	CFMutableArrayRef oldActiveSources = _activeSources;
	
	// swap _activeSources
	OSSpinLockLock(&_audioTaskThreadStatusLock);
	_activeSources = newActiveSources;
	OSSpinLockUnlock(&_audioTaskThreadStatusLock);
	
	// release the old array of sources
	CFRelease(oldActiveSources);
	
	// we can bail out right now if there are no sounds to remove
	if ([soundsToRemove count] == 0) {
		[soundsToRemove release];
		return;
	}
#if defined(DEBUG) && DEBUG > 1
	else RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"updated active sources by removing %@", soundsToRemove);
#endif
	
	// remove the sources for all expired sounds from the sound to source map and prepare the detach and delete array
	if (!_sourcesToDelete)
		_sourcesToDelete = [self _createSourceArrayFromSoundSet:soundsToRemove callbacks:&g_deleteOnReleaseAudioSourceArrayCallbacks];
	
	// detach the sources
	RX::AudioRenderer* renderer = (reinterpret_cast<RX::AudioRenderer*>([g_world audioRenderer]));
	renderer->DetachSources(_sourcesToDelete);
	
	// if automatic graph updates are enabled, we can safely delete the sources, otherwise the responsibility incurs to whatever will re-enabled automatic graph updates
	if (renderer->AutomaticGraphUpdates()) {
		CFRelease(_sourcesToDelete);
		_sourcesToDelete = NULL;
	}
	
	// done with the set
	[soundsToRemove release];
}

- (void)activateSoundGroup:(RXSoundGroup*)soundGroup {
	// WARNING: MUST RUN ON THE SCRIPT THREAD
	if ([NSThread currentThread] != [g_world scriptThread])
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"activateSoundGroup: MUST RUN ON SCRIPT THREAD" userInfo:nil];

	// cache a pointer to the audio renderer
	RX::AudioRenderer* renderer = (reinterpret_cast<RX::AudioRenderer*>([g_world audioRenderer]));
	
	// cache the sound group's sound set
	NSSet* soundGroupSounds = [soundGroup sounds];
#if defined(DEBUG)
	RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"*****************************\nactivating sound group %@ with sounds: %@", soundGroup, soundGroupSounds);
#endif
	
	// create an array of new sources
	CFMutableArrayRef sourcesToAdd = CFArrayCreateMutable(NULL, 0, &g_weakAudioSourceArrayCallbacks);
	
	// copy the active sound set to prepare the new active sound set
	NSMutableSet* newActiveSounds = [_activeSounds mutableCopy];
	
	// the set of sounds to remove is the set of active sounds minus the incoming sound group's set of sounds
	NSMutableSet* soundsToRemove = [_activeSounds mutableCopy];
	[soundsToRemove minusSet:soundGroupSounds];
	
	// process new and updated sounds
	NSEnumerator* soundEnum = [soundGroupSounds objectEnumerator];
	RXSound* sound;
	while ((sound = [soundEnum nextObject])) {
		RXSound* active_sound = [_activeSounds member:sound];
		if (!active_sound) {
			// NEW SOUND
		
			// get a decompressor
			id <MHKAudioDecompression> decompressor = [sound audioDecompressor];
			if (!decompressor) {
				RXOLog2(kRXLoggingAudio, kRXLoggingLevelError, @"failed to get audio decompressor for sound ID %hu", sound->ID);
				continue;
			}
			
			// create an audio source with the decompressor
			sound->source = new RX::CardAudioSource(decompressor, sound->gain * soundGroup->gain, sound->pan, soundGroup->loop);
			assert(sound->source);
			
			// make sure the sound doesn't have a valid detach timestamp
			sound->detachTimestampValid = NO;
			
			// add the sound to the new set of active sounds
			[newActiveSounds addObject:sound];
			
			// prepare the sourcesToAdd array
			CFArrayAppendValue(sourcesToAdd, sound->source);
			
#if defined(DEBUG) && DEBUG > 1
			RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"    added new sound %hu to the active mix (source: %p)", sound->ID, sound->source);
#endif
		} else {
			// UPDATE SOUND
			assert(active_sound->source);
			
			// update the sound's gain and pan (this does not affect the source)
			active_sound->gain = 1.0f;//sound->gain;
			active_sound->pan = sound->pan;
			
			// make sure the sound doesn't have a valid detach timestamp
			active_sound->detachTimestampValid = NO;
			
			// set source looping
			active_sound->source->SetLooping(soundGroup->loop);
			
			// ramp the source's gain
			renderer->RampSourceGain(*(active_sound->source), active_sound->gain * soundGroup->gain, RX_AUDIO_RAMP_DURATION);
			active_sound->source->SetNominalGain(active_sound->gain * soundGroup->gain);
			
			// ramp the source's stereo panning
			renderer->RampSourcePan(*(active_sound->source), active_sound->pan, RX_AUDIO_RAMP_DURATION);
			active_sound->source->SetNominalPan(active_sound->pan);
			
#if defined(DEBUG) && DEBUG > 1
			RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"    updated sound %hu in the active mix (source: %p)", sound->ID, sound->source);
#endif
		}
	}
	
	// if no fade out is requested, mark every sound not already scheduled for detach as needing detach yesterday
	if (!soundGroup->fadeOutActiveGroupBeforeActivating) {
		soundEnum = [soundsToRemove objectEnumerator];
		while ((sound = [soundEnum nextObject])) {
			if (sound->detachTimestampValid == NO) {
				sound->detachTimestampValid = YES;
				sound->rampStartTimestamp = 0;
			}
		}
	}
	
	// swap the set of active sounds (not atomic, but _activeSounds is only used on the stack thread)
	NSMutableSet* old = _activeSounds;
	_activeSounds = newActiveSounds;
	[old release];
	
	// disable automatic graph updates on the audio renderer (e.g. begin a transaction)
	renderer->SetAutomaticGraphUpdates(false);
	
	// FIXME: handle situation where there are not enough busses (in which case we would probably have to do a graph update to really release the busses)
	assert(renderer->AvailableMixerBusCount() >= (uint32_t)CFArrayGetCount(sourcesToAdd));
	
	// update active sources immediately
	[self _updateActiveSources];
	
	// _updateActiveSources will have removed faded out sounds; make sure those are no longer in soundsToRemove
	[soundsToRemove intersectSet:_activeSounds];
	
	// now that any sources bound to be detached has been, go ahead and attach as many of the new sources as possible
	if (soundGroup->fadeInOnActivation || _forceFadeInOnNextSoundGroup) {
		// disabling the sources will prevent the fade in from starting before we update the graph
		CFRange everything = CFRangeMake(0, CFArrayGetCount(sourcesToAdd));
		CFArrayApplyFunction(sourcesToAdd, everything, RXCardAudioSourceDisableApplier, [g_world audioRenderer]);
		renderer->AttachSources(sourcesToAdd);
		CFArrayApplyFunction(sourcesToAdd, everything, RXCardAudioSourceFadeInApplier, [g_world audioRenderer]);
	} else
		renderer->AttachSources(sourcesToAdd);
	
	// re-enable automatic updates; this will automatically do an update if one is needed
	renderer->SetAutomaticGraphUpdates(true);
	
	// delete any sources that were detached
	if (_sourcesToDelete) {
		CFRelease(_sourcesToDelete);
		_sourcesToDelete = NULL;
	}
	
	// enable all the new audio sources
	if (soundGroup->fadeInOnActivation || _forceFadeInOnNextSoundGroup) {
		CFRange everything = CFRangeMake(0, CFArrayGetCount(sourcesToAdd));
		CFArrayApplyFunction(sourcesToAdd, everything, RXCardAudioSourceEnableApplier, [g_world audioRenderer]);
	}
	
	// schedule a fade out ramp for all to-be-removed sources if the fade out flag is on
	if (soundGroup->fadeOutActiveGroupBeforeActivating) {
		CFMutableArrayRef sourcesToRemove = [self _createSourceArrayFromSoundSet:soundsToRemove callbacks:&g_weakAudioSourceArrayCallbacks];
		renderer->RampSourcesGain(sourcesToRemove, 0.0f, RX_AUDIO_RAMP_DURATION);
		CFRelease(sourcesToRemove);
		
		uint64_t now = RXTimingNow();
		NSEnumerator* soundEnum = [soundsToRemove objectEnumerator];
		RXSound* sound;
		while ((sound = [soundEnum nextObject])) {
			sound->rampStartTimestamp = now;
			sound->detachTimestampValid = YES;
		}
	}
	
#if defined(DEBUG) && DEBUG > 1
	RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"new active sound set: %@", newActiveSounds);
#endif
	
	// reset the fade in override flag
	_forceFadeInOnNextSoundGroup = NO;
	
	// done with sourcesToAdd
	CFRelease(sourcesToAdd);
	
	// done with the sound sets
	[soundsToRemove release];
}

- (void)playDataSound:(RXDataSound*)sound {
	// WARNING: MUST RUN ON THE SCRIPT THREAD
	if ([NSThread currentThread] != [g_world scriptThread])
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"playDataSound: MUST RUN ON SCRIPT THREAD" userInfo:nil];
	
	// cache a pointer to the audio renderer
	RX::AudioRenderer* renderer = (reinterpret_cast<RX::AudioRenderer*>([g_world audioRenderer]));
	
	// get a decompressor
	// FIXME: better error handling
	id <MHKAudioDecompression> decompressor = [sound audioDecompressor];
	if (!decompressor) {
		RXOLog2(kRXLoggingAudio, kRXLoggingLevelError, @"[ERROR] failed to get audio decompressor for sound ID %hu", sound->ID);
		return;
	}
	
	// make a source with the decompressor
	sound->source = new RX::CardAudioSource(decompressor, sound->gain, sound->pan, false);
	assert(sound->source);
	
	// disable automatic graph updates on the audio renderer (e.g. begin a transaction)
	renderer->SetAutomaticGraphUpdates(false);
	
	// add the sound to the set of active data sounds
	[_activeDataSounds addObject:sound];
	
	// set the sound's ramp start timestamp
	sound->rampStartTimestamp = RXTimingNow();
	sound->detachTimestampValid = YES;
	
	// update active sources immediately
	[self _updateActiveSources];
	
	// now that any sources bound to be detached has been, go ahead and attach the new source
	renderer->AttachSource(*(sound->source));
	
	// re-enable automatic updates. this will automatically do an update if one is needed
	renderer->SetAutomaticGraphUpdates(true);
	
	// delete any sources that were detached
	if (_sourcesToDelete) {
		CFRelease(_sourcesToDelete);
		_sourcesToDelete = NULL;
	}
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"playing data sound %@", sound);
#endif
}

- (void)_audioTaskThread:(id)object {
	// WARNING: WILL BE RUNNING ON A DEDICATED THREAD
	NSAutoreleasePool* p = [NSAutoreleasePool new];
	uint32_t cycles = 0;
	
	CFRange everything = CFRangeMake(0, 0);
	void* renderer = [g_world audioRenderer];
	
	// let's get a bit more attention
	thread_extended_policy_data_t extendedPolicy;
	extendedPolicy.timeshare = false;
	kern_return_t kr = thread_policy_set(pthread_mach_thread_np(pthread_self()), THREAD_EXTENDED_POLICY, (thread_policy_t)&extendedPolicy, THREAD_EXTENDED_POLICY_COUNT);
	
	thread_precedence_policy_data_t precedencePolicy;
	precedencePolicy.importance = 63;
	kr = thread_policy_set(pthread_mach_thread_np(pthread_self()), THREAD_PRECEDENCE_POLICY, (thread_policy_t)&precedencePolicy, THREAD_PRECEDENCE_POLICY_COUNT);
	
	while (1) {
		OSSpinLockLock(&_audioTaskThreadStatusLock);
		
		everything.length = CFArrayGetCount(_activeSources);
		CFArrayApplyFunction(_activeSources, everything, RXCardAudioSourceTaskApplier, renderer);
		
		OSSpinLockUnlock(&_audioTaskThreadStatusLock);
		
		// recycle the pool every 500 cycles
		cycles++;
		if (cycles > 500) {
			cycles = 0;
			
			[p release];
			p = [NSAutoreleasePool new];
		}
		
		// sleep 1 second until the next cycle
		sleep(1);
	}
	
	// pop the autorelease pool
	[p release];
	
	// signal anything that may be waiting on this thread to die
	semaphore_signal_all(_audioTaskThreadExitSemaphore);
}

#pragma mark -
#pragma mark riven script protocol implementation

- (void)queuePicture:(RXPicture*)picture {
	[_back_render_state->pictures addObject:picture];
	[[picture owner] retain];
}

- (void)enableMovie:(RXMovie*)movie {
	OSSpinLockLock(&_renderLock);
	
	uint32_t index = [_active_movies indexOfObject:movie];
	if (index != NSNotFound)
		[_active_movies removeObjectAtIndex:index];
	
	[_active_movies addObject:movie];
	
	if (index == NSNotFound)
		[[movie owner] retain];
	
	OSSpinLockUnlock(&_renderLock);
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"enabled movie %@, back movie list count at %d", movie, [_active_movies count]);
#endif
}


- (void)disableMovie:(RXMovie*)movie {
	OSSpinLockLock(&_renderLock);
	
	uint32_t index = [_active_movies indexOfObject:movie];
	if (index != NSNotFound) {
		[[movie movie] stop];
		[[movie owner] release];
		[_active_movies removeObjectAtIndex:index];
	}
	
	OSSpinLockUnlock(&_renderLock);
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"disabled movie %@, back movie list count at %d", movie, [_active_movies count]);
#endif
}

- (void)disableAllMovies {
	OSSpinLockLock(&_renderLock);
	
	NSEnumerator* movie_enum = [_active_movies objectEnumerator];
	RXMovie* movie;
	while ((movie = [movie_enum nextObject]))
		[[movie movie] stop];
	CFArrayApplyFunction((CFArrayRef)_active_movies, CFRangeMake(0, [_active_movies count]), rx_release_owner_applier, self);
	[_active_movies removeAllObjects];
	
	OSSpinLockUnlock(&_renderLock);
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"disabled all movies, back movie list count at %d", [_active_movies count]);
#endif
}

- (void)queueSpecialEffect:(rx_card_sfxe*)sfxe owner:(id)owner {
	if (_back_render_state->water_fx.sfxe == sfxe)
		return;
	
	_back_render_state->water_fx.sfxe = sfxe;
	_back_render_state->water_fx.current_frame = 0;
	if (sfxe)
		_back_render_state->water_fx.owner = owner;
	else
		_back_render_state->water_fx.owner = nil;
}

- (void)queueTransition:(RXTransition*)transition {	
	// queue the transition
	[_transitionQueue addObject:transition];
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"queued transition %@, queue depth=%lu", transition, [_transitionQueue count]);
#endif
}

- (void)update {
	// if we'll queue a transition, hide the cursor
	if ([_transitionQueue count] > 0)
		[self hideMouseCursor];
	
	// if a transition is ongoing, wait until its done
	mach_timespec_t waitTime = {0, kRXTransitionDuration * 1e9};
	while (_front_render_state->transition != nil)
		semaphore_timedwait(_transitionSemaphore, waitTime);
	
	// dequeue the top transition
	if ([_transitionQueue count] > 0) {
		_back_render_state->transition = [[_transitionQueue objectAtIndex:0] retain];
		[_transitionQueue removeObjectAtIndex:0];
		
#if defined(DEBUG)
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"dequeued transition %@, queue depth=%lu", _back_render_state->transition, [_transitionQueue count]);
#endif
	}
	
	// retain the water effect owner at this time, since we're about to swap the render states
	[_back_render_state->water_fx.owner retain];
	
	// indicate that this is a new render state
	_back_render_state->refresh_static = YES;
	
	// save the front render state
	struct rx_card_state_render_state* previous_front_render_state = _front_render_state;
	
	// take the render lock
	OSSpinLockLock(&_renderLock);
	
	if (_front_render_state->refresh_static) {
		// we need to merge the back render state into the front render state because we swapped before we could even render a single frame
		NSMutableArray* new_pictures = _back_render_state->pictures;
		_back_render_state->pictures = _front_render_state->pictures;
		_front_render_state->pictures = new_pictures;
		
		[_back_render_state->pictures addObjectsFromArray:new_pictures];
		[_front_render_state->pictures removeAllObjects];
	}
	
	// take the state swap lock
	OSSpinLockLock(&_state_swap_lock);
	
	// fast swap
	_front_render_state = _back_render_state;
	
	// release the state swap lock
	OSSpinLockUnlock(&_state_swap_lock);
	
	// we can resume rendering now
	OSSpinLockUnlock(&_renderLock);
	
	// set the back render state to the old front render state
	_back_render_state = previous_front_render_state;
	
	// if we had a new card, it's now in place
	_back_render_state->new_card = NO;
	
	CFArrayApplyFunction((CFArrayRef)_back_render_state->pictures, CFRangeMake(0, [_back_render_state->pictures count]), rx_release_owner_applier, self);
	[_back_render_state->pictures removeAllObjects];
	
	// release the back render state water effect's owner, since it is no longer active
	[_back_render_state->water_fx.owner release];
	
	// copy the front water_fx state into the back water_fx state since water sfxe has to be explicitely enabled or disabled
	_back_render_state->water_fx = _front_render_state->water_fx;
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"swapped render state, front card=%@", _front_render_state->card);
#endif
	
	// if the front card has changed, we need to run the new card's "start rendering" program
	if (_front_render_state->new_card) {
		// reclaim the back render state's card
		[_back_render_state->card release];
		_back_render_state->card = _front_render_state->card;
		
		// run the new front card's "start rendering" script
		[sengine startRendering];
		
		// show the mouse cursor now that the card switch is done
		[self showMouseCursor];
	}
}

#pragma mark -
#pragma mark card switching

- (void)_postCardSwitchNotification:(RXCard*)newCard {
	// WARNING: MUST RUN ON THE MAIN THREAD
	[[NSNotificationCenter defaultCenter] postNotificationName:@"RXActiveCardDidChange" object:newCard];
}

- (void)_broadcastCurrentCard:(NSNotification*)notification {
	OSSpinLockLock(&_state_swap_lock);
	[self _postCardSwitchNotification:_front_render_state->card];
	OSSpinLockUnlock(&_state_swap_lock);
}

- (void)_switchCardWithSimpleDescriptor:(RXSimpleCardDescriptor*)simpleDescriptor {
	// WARNING: MUST RUN ON THE SCRIPT THREAD
	if ([NSThread currentThread] != [g_world scriptThread])
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_switchCardWithSimpleDescriptor: MUST RUN ON SCRIPT THREAD" userInfo:nil];
	
	RXCard* new_card = nil;
	
	// because this method will always execute in the script thread, we do not have to protect access to the front card
	RXCard* front_card = _front_render_state->card;
	
	// if we're switching to the same card, don't allocate another copy of it
	if (front_card) {
		RXCardDescriptor* activeDescriptor = [front_card descriptor];
		RXStack* activeStack = [activeDescriptor valueForKey:@"parent"];
		NSNumber* activeID = [activeDescriptor valueForKey:@"ID"];
		if ([[activeStack key] isEqualToString:simpleDescriptor->parentName] && simpleDescriptor->cardID == [activeID unsignedShortValue]) {
			new_card = [front_card retain];
#if (DEBUG)
			RXOLog(@"reloading front card: %@", front_card);
#endif
		}
	}
	
	// if we're switching to a different card, create it
	if (new_card == nil) {
		// if we don't have the stack, bail
		RXStack* newStack = [g_world activeStackWithKey:simpleDescriptor->parentName];
		if (!newStack) {
#if defined(DEBUG)
			RXOLog(@"aborting _switchCardWithSimpleDescriptor because stack %@ could not be loaded", simpleDescriptor->parentName);
#endif
			return;
		}
		
		// FIXME: need to be smarter about card loading (cache, locality, etc)
		// load the new card in
		RXCardDescriptor* newCardDescriptor = [[RXCardDescriptor alloc] initWithStack:newStack ID:simpleDescriptor->cardID];
		if (!newCardDescriptor)
			@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"COULD NOT FIND CARD IN STACK" userInfo:nil]; 
		
		new_card = [[RXCard alloc] initWithCardDescriptor:newCardDescriptor];
		[newCardDescriptor release];
		
#if (DEBUG)
		RXOLog(@"switch card: {from=%@, to=%@}", _front_render_state->card, new_card);
#endif
	}
	
	// setup the back render state; notice that the ownership of new_card is transferred to the back render state and thus we will not need a release elsewhere to match the card's allocation
	_back_render_state->card = new_card;
	_back_render_state->new_card = YES;
	_back_render_state->transition = nil;
	
	// run the stop rendering script on the old card
	[sengine stopRendering];
	
	// we have to update the current card in the game state now, otherwise refresh card commands in the prepare for rendering script will jump back to the old card
	[[g_world gameState] setCurrentCard:[[new_card descriptor] simpleDescriptor]];
	[sengine setCard:new_card];
	
	// run the prepare for rendering script on the new card
	[sengine prepareForRendering];
	
	// notify that the front card has changed
	[self performSelectorOnMainThread:@selector(_postCardSwitchNotification:) withObject:new_card waitUntilDone:NO];
}

- (void)_clearActiveCard {
	// WARNING: MUST RUN ON THE SCRIPT THREAD
	if ([NSThread currentThread] != [g_world scriptThread])
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_clearActiveCard: MUST RUN ON SCRIPT THREAD" userInfo:nil];
	
	// setup the back render state
	_back_render_state->card = nil;
	_back_render_state->new_card = YES;
	_back_render_state->transition = nil;
	
	// run the stop rendering script on the old card; note that we do not need to protect access to the front card since this method will always execute on the script thread
	[sengine stopRendering];
	
	// wipe out the transition queue
	[_transitionQueue removeAllObjects];
	
	// hide the mouse cursor
	[self hideMouseCursor];
	
	// fake a swap render state
	[self update];
	
	// notify that the front card has changed
	[self performSelectorOnMainThread:@selector(_postCardSwitchNotification:) withObject:nil waitUntilDone:NO];
}

- (void)setActiveCardWithStack:(NSString*)stackKey ID:(uint16_t)cardID waitUntilDone:(BOOL)wait {
	// WARNING: CAN RUN ON ANY THREAD
	if (!stackKey)
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"stackKey CANNOT BE NIL" userInfo:nil];
	
	RXSimpleCardDescriptor* des = [[RXSimpleCardDescriptor alloc] initWithStackName:stackKey ID:cardID];
	
	// FIXME: we need to be smarter about stack management; right now, we load a stack when it is first needed and keep it in memory forever
	// make sure the requested stack has been loaded
	RXStack* stack = [g_world activeStackWithKey:des->parentName];
	if (!stack)
		[g_world loadStackWithKey:des->parentName waitUntilDone:YES];
	
	// hide the mouse cursor and switch card on the script thread
	[self hideMouseCursor];
	[self performSelector:@selector(_switchCardWithSimpleDescriptor:) withObject:des inThread:[g_world scriptThread] waitUntilDone:wait];
	
	// if we have a card redirect entry, queue the final destination card switch
	RXSimpleCardDescriptor* switchTableDestination = [[[[RXEditionManager sharedEditionManager] currentEdition] valueForKey:@"stackSwitchTables"] objectForKey:des];
	if (switchTableDestination) {		
		RXTransition* transition = [[RXTransition alloc] initWithCode:16 region:NSMakeRect(0.f, 0.f, kRXCardViewportSize.width, kRXCardViewportSize.height)];
		[self performSelector:@selector(queueTransition:) withObject:transition inThread:[g_world scriptThread] waitUntilDone:wait];
		[transition release];
		
		[self setActiveCardWithStack:switchTableDestination->parentName ID:switchTableDestination->cardID waitUntilDone:wait];
	}
	
	[des release];
}

- (void)clearActiveCardWaitingUntilDone:(BOOL)wait {
	[self performSelector:@selector(_clearActiveCard) withObject:nil inThread:[g_world scriptThread] waitUntilDone:wait];
}

#pragma mark -
#pragma mark graphics rendering

- (void)_renderCardWithTimestamp:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	
	// read the front render state pointer once and alias it for this method
	struct rx_card_state_render_state* r = _front_render_state;
	
	// alias the global render context state object
//	NSObject<RXOpenGLStateProtocol>* gl_state = g_renderContextState;
	
	// render object enumeration variables
	NSEnumerator* renderListEnumerator;
	id<RXRenderingProtocol> renderObject;
	
	// draw in the dynamic RT
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _fbos[RX_CARD_DYNAMIC_RENDER_INDEX]); glReportError();
	
	// use the rect texture program
	glUseProgram(_single_rect_texture_program); glReportError();
	
	// flip the y axis
	glMatrixMode(GL_MODELVIEW);
	glTranslatef(0.f, kRXCardViewportSize.height, 0.f);
	glScalef(1.0f, -1.0f, 1.0f);
	
	// render static card pictures only when necessary
	if (r->refresh_static) {		
		// render each picture
		renderListEnumerator = [r->pictures objectEnumerator];
		while ((renderObject = [renderListEnumerator nextObject]))
			[renderObject render:outputTime inContext:cgl_ctx framebuffer:_fbos[RX_CARD_DYNAMIC_RENDER_INDEX]];
	}
	
	if (r->water_fx.sfxe) {		
		// map pointer for the water buffer
		void* water_draw_ptr = NULL;
		
		// if we refreshed pictures, we need to reset the special effect and copy the RT back to main memory
		if (r->refresh_static) {
			r->water_fx.current_frame = 0;
			r->water_fx.frame_timestamp = 0;
			
			// we need to immediately readback the dynamic RT into the water buffer
			glBindBuffer(GL_PIXEL_PACK_BUFFER, _water_buffer); glReportError();
			glReadPixels(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL); glReportError();
			
			// copy the water buffer into the water readback buffer
			water_draw_ptr = glMapBuffer(GL_PIXEL_PACK_BUFFER, GL_READ_WRITE); glReportError();
			memcpy(_water_readback_buffer, water_draw_ptr, kRXCardViewportSize.width * kRXCardViewportSize.height << 2);
			
//			int fd = open("frame_dump", O_TRUNC | O_CREAT | O_RDWR, 0600);
//			write(fd, water_draw_ptr, kRXCardViewportSize.width * kRXCardViewportSize.height << 2);
//			close(fd);
			
			glBindBuffer(GL_PIXEL_PACK_BUFFER, 0); glReportError();
		}
		
		// if the special effect frame timestamp is 0 or expired, update the special effect texture
		double fps_inverse = 1.0 / r->water_fx.sfxe->record->fps;
		if (r->water_fx.frame_timestamp == 0 || RXTimingTimestampDelta(outputTime->hostTime, r->water_fx.frame_timestamp) >= fps_inverse) {
			// bind the water buffer on the unpack buffer target
			glBindBuffer(GL_PIXEL_UNPACK_BUFFER, _water_buffer); glReportError();
			
			// if the water buffer has not been mapped yet, do so now
			if (!water_draw_ptr) {
				water_draw_ptr = glMapBuffer(GL_PIXEL_UNPACK_BUFFER, GL_WRITE_ONLY); glReportError();
			}
			
			// run the water microprogram for the current sfxe frame
			uint16_t* mp = (uint16_t*)BUFFER_OFFSET(r->water_fx.sfxe->record, r->water_fx.sfxe->offsets[r->water_fx.current_frame]);
			uint16_t draw_row = r->water_fx.sfxe->record->top;
			while (*mp != 4) {
				if (*mp == 1) {
					draw_row++;
				} else if (*mp == 3) {
					memcpy(BUFFER_OFFSET(water_draw_ptr, (draw_row * kRXCardViewportSize.width + mp[1]) << 2), BUFFER_OFFSET(_water_readback_buffer, (mp[3] * kRXCardViewportSize.width + mp[2]) << 2), mp[4] << 2);
					mp += 4;
				} else
					abort();
				
				mp++;
			}
			
			// unmap the water buffer to commit the update to GL
			glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER);
			
			// update the dynamic RT texture with the unpack buffer
			glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _textures[RX_CARD_DYNAMIC_RENDER_INDEX]); glReportError();
			glTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, 0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
			
			// bind 0 to the unpack buffer target
			glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0); glReportError();
			
			// increment the special effect frame counter
			r->water_fx.current_frame = (r->water_fx.current_frame + 1) % r->water_fx.sfxe->record->frame_count;
			r->water_fx.frame_timestamp = outputTime->hostTime;
		}
	}
	
	// render movies at the very end
	renderListEnumerator = [_active_movies objectEnumerator];
	while ((renderObject = [renderListEnumerator nextObject]))
		_movieRenderDispatch.imp(renderObject, _movieRenderDispatch.sel, outputTime, cgl_ctx, _fbos[RX_CARD_DYNAMIC_RENDER_INDEX]);
	
	// un-flip the y axis
	glLoadIdentity();
	
	// static content has been refreshed at the end of this method
	r->refresh_static = NO;
}

- (void)_postFlushCard:(const CVTimeStamp*)outputTime {
	NSEnumerator* e = [_active_movies objectEnumerator];
	RXMovie* movie;
	while ((movie = [e nextObject]))
		_movieFlushTasksDispatch.imp(movie, _movieFlushTasksDispatch.sel, outputTime);
}

- (void)_updateInventoryWithTimestamp:(const CVTimeStamp*)outputTime context:(CGLContextObj)cgl_ctx {
	RXGameState* game_state = [g_world gameState];
	
	// if the engine says the inventory should not be shown, set the number of inventory items to 0 and return
	if (![game_state unsigned32ForKey:@"ainventory"]) {
		_inventoryItemCount = 0;
		return;
	}
	
	// FIXME: right now we set the number of items to the maximum, irrespective of game state
	_inventoryItemCount = RX_MAX_INVENTORY_ITEMS;
	
	glBindBuffer(GL_ARRAY_BUFFER, _cardCompositeVBO); glReportError();
	GLfloat* buffer = (GLfloat*)glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY);
	
	GLfloat* positions = buffer + 16;
	GLfloat* tex_coords0 = positions + 2;
	
	// compute the total inventory region width based on the number of items in the inventory
	float total_inventory_width = _inventoryRegions[0].size.width;
	for (GLuint inventory_i = 1; inventory_i < _inventoryItemCount; inventory_i++)
		total_inventory_width += _inventoryRegions[inventory_i].size.width + RX_INVENTORY_MARGIN;
	
	// compute the first item's position
	_inventoryRegions[0].origin.x = kRXCardViewportOriginOffset.x + (kRXCardViewportSize.width / 2.0f) - (total_inventory_width / 2.0f);
	_inventoryRegions[0].origin.y = (kRXCardViewportOriginOffset.y / 2.0f) - (_inventoryRegions[0].size.height / 2.0f);
	
	// compute the position of any additional item based on the position of the previous item
	for (GLuint inventory_i = 1; inventory_i < _inventoryItemCount; inventory_i++) {
		_inventoryRegions[inventory_i].origin.x = _inventoryRegions[inventory_i - 1].origin.x + _inventoryRegions[inventory_i - 1].size.width + RX_INVENTORY_MARGIN;
		_inventoryRegions[inventory_i].origin.y = (kRXCardViewportOriginOffset.y / 2.0f) - (_inventoryRegions[1].size.height / 2.0f);
	}
	
	// compute vertex positions and texture coordinates for the items
	for (GLuint inventory_i = 0; inventory_i < _inventoryItemCount; inventory_i++) {
		positions[0] = _inventoryRegions[inventory_i].origin.x; positions[1] = _inventoryRegions[inventory_i].origin.y;
		tex_coords0[0] = 0.0f; tex_coords0[1] = _inventoryRegions[inventory_i].size.height;
		positions += 4; tex_coords0 += 4;
		
		positions[0] = _inventoryRegions[inventory_i].origin.x + _inventoryRegions[inventory_i].size.width; positions[1] = _inventoryRegions[inventory_i].origin.y;
		tex_coords0[0] = _inventoryRegions[inventory_i].size.width; tex_coords0[1] = _inventoryRegions[inventory_i].size.height;
		positions += 4; tex_coords0 += 4;
		
		positions[0] = _inventoryRegions[inventory_i].origin.x; positions[1] = _inventoryRegions[inventory_i].origin.y + _inventoryRegions[inventory_i].size.height;
		tex_coords0[0] = 0.0f; tex_coords0[1] = 0.0f;
		positions += 4; tex_coords0 += 4;
		
		positions[0] = _inventoryRegions[inventory_i].origin.x + _inventoryRegions[inventory_i].size.width; positions[1] = _inventoryRegions[inventory_i].origin.y + _inventoryRegions[inventory_i].size.height;
		tex_coords0[0] = _inventoryRegions[inventory_i].size.width; tex_coords0[1] = 0.0f;
		positions += 4; tex_coords0 += 4;
	}
	
	// unmap and flush the card composite VBO
	if (GLEE_APPLE_flush_buffer_range)
		glFlushMappedBufferRangeAPPLE(GL_ARRAY_BUFFER, 16 * sizeof(GLfloat), _inventoryItemCount * 16 * sizeof(GLfloat));
	glUnmapBuffer(GL_ARRAY_BUFFER); glReportError();
	
	// compute the hotspot regions by scaling the rendering regions
	rx_rect_t contentRect = RXEffectiveRendererFrame();
	float scale_x = (float)contentRect.size.width / (float)kRXRendererViewportSize.width;
	float scale_y = (float)contentRect.size.height / (float)kRXRendererViewportSize.height;
	
	for (GLuint inventory_i = 0; inventory_i < _inventoryItemCount; inventory_i++) {
		_inventoryHotspotRegions[inventory_i].origin.x = contentRect.origin.x + _inventoryRegions[inventory_i].origin.x * scale_x;
		_inventoryHotspotRegions[inventory_i].origin.y = contentRect.origin.y + _inventoryRegions[inventory_i].origin.y * scale_y;
		_inventoryHotspotRegions[inventory_i].size.width = _inventoryRegions[inventory_i].size.width * scale_x;
		_inventoryHotspotRegions[inventory_i].size.height = _inventoryRegions[inventory_i].size.height * scale_y;
	}
}

- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx framebuffer:(GLuint)fbo {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	OSSpinLockLock(&_renderLock);
	
	// alias the render context state object pointer
	NSObject<RXOpenGLStateProtocol>* gl_state = g_renderContextState;
	
	// we need an inner pool within the scope of that lock, or we run the risk of autoreleased enumerators causing objects that should be deallocated on the main thread not to be
	NSAutoreleasePool* p = [NSAutoreleasePool new];
	
	// do nothing if there is no front card
	if (!_front_render_state->card)
		goto exit_render;
	
	// transition priming
	if (_front_render_state->transition && ![_front_render_state->transition isPrimed]) {
		// render the current frame in a texture
		GLuint transitionSourceTexture;
		glGenTextures(1, &transitionSourceTexture);
		
		// disable client storage because it's incompatible with allocating texture space with NULL (which is what we want when copying a texture)
		glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_FALSE);
		
		// bind the transition source texture
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, transitionSourceTexture); glReportError();
		
		// texture parameters
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glReportError();
		
		// re-enable client storage
		glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
		
		// bind the dynamic render FBO
		glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _fbos[RX_CARD_DYNAMIC_RENDER_INDEX]); glReportError();
		
		// copy framebuffer
		glCopyTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, 0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height, 0); glReportError();
		
		// give ownership of that texture to the transition
		[_front_render_state->transition primeWithSourceTexture:transitionSourceTexture outputTime:outputTime];
	}
	
	// render the front card
	render_card_imp(self, render_card_sel, outputTime, cgl_ctx);
	
	// final composite (active card + transitions + other special effects)
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, fbo); glReportError();
	glClear(GL_COLOR_BUFFER_BIT);
	
	if (_front_render_state->transition && [_front_render_state->transition isPrimed]) {
		// compute the parametric transition parameter based on current time, start time and duration
		float t = RXTimingTimestampDelta(outputTime->hostTime, _front_render_state->transition->startTime) / _front_render_state->transition->duration;
		if (t > 1.0f)
			t = 1.0f;
		
		if (t >= 1.0f) {
#if defined(DEBUG)
			RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"transition %@ completed, queue depth=%lu", _front_render_state->transition, [_transitionQueue count]);
#endif
			[_front_render_state->transition release];
			_front_render_state->transition = nil;
			
			// signal we're no longer running a transition
			semaphore_signal_all(_transitionSemaphore);
			
			// show the cursor again
			[self showMouseCursor];
			
			// use the regular rect texture program
			glUseProgram(_single_rect_texture_program); glReportError();
		} else {
			// determine which transition shading program to use based on the transition type
			struct rx_transition_program* transition = NULL;
			switch (_front_render_state->transition->type) {
				case RXTransitionDissolve:
					transition = &_dissolve;
					break;
				
				case RXTransitionSlide:
					if (_front_render_state->transition->pushOld && _front_render_state->transition->pushNew)
						transition = _push + _front_render_state->transition->direction;
					else if (_front_render_state->transition->pushOld)
						transition = _slide_out + _front_render_state->transition->direction;
					else if (_front_render_state->transition->pushNew)
						transition = _slide_in + _front_render_state->transition->direction;
					else
						transition = _swipe + _front_render_state->transition->direction;
					break;
			}
			
			// use the transition's program and update its t and margin uniforms
			glUseProgram(transition->program); glReportError();
			glUniform1f(transition->t_uniform, t); glReportError();
			
			// bind the transition source texture on unit 1
			glActiveTexture(GL_TEXTURE1); glReportError();
			glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _front_render_state->transition->sourceTexture); glReportError();
		}
	} else {
		glUseProgram(_single_rect_texture_program); glReportError();
	}
	
	// bind the dynamic card content texture to unit 0
	glActiveTexture(GL_TEXTURE0); glReportError();
	glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _textures[RX_CARD_DYNAMIC_RENDER_INDEX]); glReportError();
	
	// bind the card composite VAO
	[gl_state bindVertexArrayObject:_cardCompositeVAO];
	
	// draw the card composite
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); glReportError();
	
	// update and draw the inventory
	[self _updateInventoryWithTimestamp:outputTime context:cgl_ctx];
	
	if (_inventoryAlphaFactor > 0.f && _inventoryItemCount > 0) {
		if (_inventoryAlphaFactor < 1.f) {
			glBlendColor(1.f, 1.f, 1.f, _inventoryAlphaFactor);
			glBlendFuncSeparate(GL_CONSTANT_ALPHA, GL_ONE_MINUS_CONSTANT_ALPHA, GL_CONSTANT_ALPHA, GL_ONE_MINUS_CONSTANT_ALPHA);
			glBlendEquationSeparate(GL_FUNC_ADD, GL_FUNC_ADD);
			glEnable(GL_BLEND);
		}
		
		glUseProgram(_single_rect_texture_program); glReportError();
		for (GLuint inventory_i = 0; inventory_i < _inventoryItemCount; inventory_i++) {
			glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _inventoryTextures[inventory_i]); glReportError();
			glDrawArrays(GL_TRIANGLE_STRIP, 4 + 4 * inventory_i, 4); glReportError();
		}
		
		if (_inventoryAlphaFactor < 1.f)
			glDisable(GL_BLEND);
	}
	
exit_render:
	[p release];
	OSSpinLockUnlock(&_renderLock);
}

- (void)_renderInGlobalContext:(CGLContextObj)cgl_ctx {
	// alias the render context state object pointer
	NSObject<RXOpenGLStateProtocol>* gl_state = g_renderContextState;
	RXCard* front_card = nil;
	
	// render hotspots
	if (RXEngineGetBool(@"rendering.hotspots_info")) {
		// need to take the render lock to avoid a race condition with the script thread executing a card swap
		if (!front_card) {
			OSSpinLockLock(&_state_swap_lock);
			front_card = [_front_render_state->card retain];
			OSSpinLockUnlock(&_state_swap_lock);
		}
		
		NSArray* activeHotspots = [sengine activeHotspots];
		if ([activeHotspots count] > RX_MAX_RENDER_HOTSPOT)
			activeHotspots = [activeHotspots subarrayWithRange:NSMakeRange(0, RX_MAX_RENDER_HOTSPOT)];
		
		glBindBuffer(GL_ARRAY_BUFFER, _hotspotDebugRenderVBO);
		GLfloat* attribs = (GLfloat*)glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY);
		
		NSEnumerator* hotspots = [activeHotspots objectEnumerator];
		RXHotspot* hotspot;
		GLint primitive_index = 0;
		while ((hotspot = [hotspots nextObject])) {
			_hotspotDebugRenderFirstElementArray[primitive_index] = primitive_index * 4;
			_hotspotDebugRenderElementCountArray[primitive_index] = 4;
			
			NSRect frame = [hotspot worldViewFrame];
			
			attribs[0] = frame.origin.x;
			attribs[1] = frame.origin.y;
			attribs[2] = 0.0f;
			attribs[3] = 1.0f;
			attribs[4] = 0.0f;
			attribs[5] = 1.0f;
			attribs += 6;
			
			attribs[0] = frame.origin.x + frame.size.width;
			attribs[1] = frame.origin.y;
			attribs[2] = 0.0f;
			attribs[3] = 1.0f;
			attribs[4] = 0.0f;
			attribs[5] = 1.0f;
			attribs += 6;
			
			attribs[0] = frame.origin.x + frame.size.width;
			attribs[1] = frame.origin.y + frame.size.height;
			attribs[2] = 0.0f;
			attribs[3] = 1.0f;
			attribs[4] = 0.0f;
			attribs[5] = 1.0f;
			attribs += 6;
			
			attribs[0] = frame.origin.x;
			attribs[1] = frame.origin.y + frame.size.height;
			attribs[2] = 0.0f;
			attribs[3] = 1.0f;
			attribs[4] = 0.0f;
			attribs[5] = 1.0f;
			attribs += 6;
			
			primitive_index++;
		}
		
		for (GLuint inventory_i = 0; inventory_i < _inventoryItemCount; inventory_i++) {
			_hotspotDebugRenderFirstElementArray[primitive_index] = primitive_index * 4;
			_hotspotDebugRenderElementCountArray[primitive_index] = 4;
			
			NSRect frame = _inventoryHotspotRegions[inventory_i];
			
			attribs[0] = frame.origin.x;
			attribs[1] = frame.origin.y;
			attribs[2] = 0.0f;
			attribs[3] = 1.0f;
			attribs[4] = 0.0f;
			attribs[5] = 1.0f;
			attribs += 6;
			
			attribs[0] = frame.origin.x + frame.size.width;
			attribs[1] = frame.origin.y;
			attribs[2] = 0.0f;
			attribs[3] = 1.0f;
			attribs[4] = 0.0f;
			attribs[5] = 1.0f;
			attribs += 6;
			
			attribs[0] = frame.origin.x + frame.size.width;
			attribs[1] = frame.origin.y + frame.size.height;
			attribs[2] = 0.0f;
			attribs[3] = 1.0f;
			attribs[4] = 0.0f;
			attribs[5] = 1.0f;
			attribs += 6;
			
			attribs[0] = frame.origin.x;
			attribs[1] = frame.origin.y + frame.size.height;
			attribs[2] = 0.0f;
			attribs[3] = 1.0f;
			attribs[4] = 0.0f;
			attribs[5] = 1.0f;
			attribs += 6;
			
			primitive_index++;
		}
		
		if (GLEE_APPLE_flush_buffer_range)
			glFlushMappedBufferRangeAPPLE(GL_ARRAY_BUFFER, 0, [activeHotspots count] * 24 * sizeof(GLfloat));
		glUnmapBuffer(GL_ARRAY_BUFFER); glReportError();
		
		[gl_state bindVertexArrayObject:_hotspotDebugRenderVAO];
		glMultiDrawArrays(GL_LINE_LOOP, _hotspotDebugRenderFirstElementArray, _hotspotDebugRenderElementCountArray, [activeHotspots count] + _inventoryItemCount); glReportError();
		
		[gl_state bindVertexArrayObject:0];
	}
	
	// character buffer for debug strings to render
	char debug_buffer[100];
	
	// VA for the background strip we'll paint before a debug string
	NSPoint background_origin = NSMakePoint(9.5, 19.5);
	GLfloat background_strip[12] = {
		background_origin.x, background_origin.y, 0.0f,
		background_origin.x, background_origin.y, 0.0f,
		background_origin.x, background_origin.y + 13.0f, 0.0f,
		background_origin.x, background_origin.y + 13.0f, 0.0f
	};
	
	// setup the pipeline to use the client memory VA we defined above
	[gl_state bindVertexArrayObject:0];
	glBindBuffer(GL_ARRAY_BUFFER, 0);
	glVertexPointer(3, GL_FLOAT, 0, background_strip);
	glEnableClientState(GL_VERTEX_ARRAY);
	
	// card info
	if (RXEngineGetBool(@"rendering.card_info")) {
		// need to take the render lock to avoid a race condition with the script thread executing a card swap
		if (!front_card) {
			OSSpinLockLock(&_state_swap_lock);
			front_card = [_front_render_state->card retain];
			OSSpinLockUnlock(&_state_swap_lock);
		}
		
		if (front_card) {		
			RXSimpleCardDescriptor* scd = [[front_card descriptor] simpleDescriptor];
			snprintf(debug_buffer, 100, "card: %s %d", [scd->parentName cStringUsingEncoding:NSASCIIStringEncoding], scd->cardID);
			
			background_strip[3] = background_origin.x + glutBitmapLength(GLUT_BITMAP_8_BY_13, (unsigned char*)debug_buffer);
			background_strip[9] = background_origin.x + glutBitmapLength(GLUT_BITMAP_8_BY_13, (unsigned char*)debug_buffer);
			
			glColor4f(0.0f, 0.0f, 0.0f, 1.0f);
			glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
			
			glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
			glRasterPos3d(10.5f, background_origin.y + 1.0, 0.0f);
			size_t l = strlen(debug_buffer);
			for (size_t i = 0; i < l; i++)
				glutBitmapCharacter(GLUT_BITMAP_8_BY_13, debug_buffer[i]);
		}
		
		// go up to the next debug line
		background_origin.y += 13.0;
		background_strip[1] = background_strip[7];
		background_strip[4] = background_strip[7];
		background_strip[7] = background_strip[7] + 13.0f;
		background_strip[10] = background_strip[7];
	}
	
	// mouse info
	if (RXEngineGetBool(@"rendering.mouse_info")) {
		NSRect mouse = [self mouseVector];
		
		float theta = 180.0f * atan2f(mouse.size.height, mouse.size.width) * M_1_PI;
		float r = sqrtf((mouse.size.height * mouse.size.height) + (mouse.size.width * mouse.size.width));
		
		snprintf(debug_buffer, 100, "mouse vector: (%d, %d) (%.3f, %.3f) (%.3f, %.3f)", (int)mouse.origin.x, (int)mouse.origin.y, mouse.size.width, mouse.size.height, theta, r);
		
		background_strip[3] = background_origin.x + glutBitmapLength(GLUT_BITMAP_8_BY_13, (unsigned char*)debug_buffer);
		background_strip[9] = background_origin.x + glutBitmapLength(GLUT_BITMAP_8_BY_13, (unsigned char*)debug_buffer);
		
		glColor4f(0.0f, 0.0f, 0.0f, 1.0f);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		
		glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
		glRasterPos3d(10.5f, background_origin.y + 1.0, 0.0f);
		size_t l = strlen(debug_buffer);
		for (size_t i = 0; i < l; i++)
			glutBitmapCharacter(GLUT_BITMAP_8_BY_13, debug_buffer[i]);
		
		// go up to the next debug line
		background_origin.y += 13.0;
		background_strip[1] = background_strip[7];
		background_strip[4] = background_strip[7];
		background_strip[7] = background_strip[7] + 13.0f;
		background_strip[10] = background_strip[7];
	}
	
	// hotspots info (part 2)
	if (RXEngineGetBool(@"rendering.hotspots_info")) {
		OSSpinLockLock(&_state_swap_lock);
		RXHotspot* hotspot = (_currentHotspot >= (RXHotspot*)0x1000) ? [_currentHotspot retain] : _currentHotspot;
		OSSpinLockUnlock(&_state_swap_lock);
		
		if (hotspot >= (RXHotspot*)0x1000)
			snprintf(debug_buffer, 100, "current hotspot: %s", [[hotspot description] cStringUsingEncoding:NSASCIIStringEncoding]);
		else if (hotspot)
			snprintf(debug_buffer, 100, "current hotspot: inventory %d", (int)hotspot);
		else
			snprintf(debug_buffer, 100, "current hotspot: none");
		
		background_strip[3] = background_origin.x + glutBitmapLength(GLUT_BITMAP_8_BY_13, (unsigned char*)debug_buffer);
		background_strip[9] = background_origin.x + glutBitmapLength(GLUT_BITMAP_8_BY_13, (unsigned char*)debug_buffer);
		
		glColor4f(0.0f, 0.0f, 0.0f, 1.0f);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		
		glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
		glRasterPos3d(10.5f, background_origin.y + 1.0, 0.0f);
		size_t l = strlen(debug_buffer);
		for (size_t i = 0; i < l; i++)
			glutBitmapCharacter(GLUT_BITMAP_8_BY_13, debug_buffer[i]);
		
		if (hotspot >= (RXHotspot*)0x1000)
			[hotspot release];
	}
	
	// re-disable the VA in VAO 0
	glDisableClientState(GL_VERTEX_ARRAY);
	
	// release front_card
	[front_card release];
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	OSSpinLockLock(&_renderLock);
	
	// we need an inner pool within the scope of that lock, or we run the risk of autoreleased enumerators causing objects that should be deallocated on the main thread not to be
	NSAutoreleasePool* p = [NSAutoreleasePool new];
	
	// do nothing if there is no front card
	if (!_front_render_state->card)
		goto exit_flush_tasks;
	
	post_flush_card_imp(self, post_flush_card_sel, outputTime);
	
exit_flush_tasks:
	[p release];
	OSSpinLockUnlock(&_renderLock);
}

#pragma mark -
#pragma mark user event handling

- (NSRect)mouseVector {
	OSSpinLockLock(&_mouseVectorLock);
	NSRect r = _mouseVector;
	OSSpinLockUnlock(&_mouseVectorLock);
	return r;
}

- (void)resetMouseVector {
	OSSpinLockLock(&_mouseVectorLock);
	if (isfinite(_mouseVector.size.width)) {
		_mouseVector.origin.x = _mouseVector.origin.x + _mouseVector.size.width;
		_mouseVector.origin.y = _mouseVector.origin.y + _mouseVector.size.height;
		_mouseVector.size.width = 0.0;
		_mouseVector.size.height = 0.0;
	}
	OSSpinLockUnlock(&_mouseVectorLock);
}

- (void)showMouseCursor {
	[self enableHotspotHandling];
	
	int32_t updated_counter = OSAtomicDecrement32Barrier(&_cursor_hide_counter);
	assert(updated_counter >= 0);
	
	if (updated_counter == 0) {
		// if the hotspot handling disable counter is at 0, updateHotspotState ran and updated the cursor; so if it's > 0, we need to restore the backup
		if (_hotspot_handling_disable_counter > 0)
			[g_worldView setCursor:_hidden_cursor];
	
		[_hidden_cursor release];
		_hidden_cursor = nil;
	}
}

- (void)hideMouseCursor {
	[self disableHotspotHandling];
	
	int32_t updated_counter = OSAtomicIncrement32Barrier(&_cursor_hide_counter);
	assert(updated_counter >= 0);
	
	if (updated_counter == 1) {
		_hidden_cursor = [[g_worldView cursor] retain];
		[g_worldView setCursor:[g_world invisibleCursor]];
	}
}

- (void)setMouseCursor:(uint16_t)cursorID {
	NSCursor* new_cursor = [g_world cursorForID:cursorID];
	if (_cursor_hide_counter > 0) {
		id old = _hidden_cursor;
		_hidden_cursor = [new_cursor retain];
		[old release];
	} else
		[g_worldView setCursor:new_cursor];
}

- (void)enableHotspotHandling {
	int32_t updated_counter = OSAtomicDecrement32Barrier(&_hotspot_handling_disable_counter);
	assert(updated_counter >= 0);
	
	if (updated_counter == 0)
		[self updateHotspotState];
}

- (void)disableHotspotHandling {
	int32_t updated_counter = OSAtomicIncrement32Barrier(&_hotspot_handling_disable_counter);
	assert(updated_counter >= 0);
	
	if (updated_counter == 1)
		[self updateHotspotState];
}

- (void)updateHotspotState {
	// NOTE: this method must run on the main thread and will bounce itself there if needed
	if (!pthread_main_np()) {
		[self performSelectorOnMainThread:@selector(updateHotspotState) withObject:nil waitUntilDone:NO];
		return;
	}
	
	// if hotspot handling is disabled, simply return
	if (_hotspot_handling_disable_counter > 0) {
		return;
	}
	
	// hotspot updates cannot occur during a card switch
	OSSpinLockLock(&_state_swap_lock);
	
	// check if hotspot handling is disabled again (last time, this is only to handle the situation where we might have slept a little while on the spin lock
	if (_hotspot_handling_disable_counter > 0) {
		OSSpinLockUnlock(&_state_swap_lock);
		return;
	}
	
	// get the mouse vector using the getter since it will take the spin lock and return a copy
	NSRect mouse_vector = [self mouseVector];
	
	// get the front card's active hotspots
	NSArray* active_hotspots = [sengine activeHotspots];

	// if the mouse is below the game viewport, bring up the alpha of the inventory to 1; otherwise set it to 0.5
	if (NSPointInRect(mouse_vector.origin, [(NSView*)g_worldView bounds]) && mouse_vector.origin.y < kRXCardViewportOriginOffset.y)
		_inventoryAlphaFactor = 1.f;
	else
		_inventoryAlphaFactor = 0.5f;
	
	// find over which hotspot the mouse is
	NSEnumerator* hotspots_enum = [active_hotspots objectEnumerator];
	RXHotspot* hotspot;
	while ((hotspot = [hotspots_enum nextObject])) {
		if (NSPointInRect(mouse_vector.origin, [hotspot worldViewFrame]))
			break;
	}
	
	// now check if we're over one of the inventory regions
	if (!hotspot) {
		for (GLuint inventory_i = 0; inventory_i < _inventoryItemCount; inventory_i++) {
			if (NSPointInRect(mouse_vector.origin, _inventoryHotspotRegions[inventory_i])) {
				// set hotspot to the inventory item index (plus one to avoid the value 0); the following block of code will check if hotspot is not 0 and below PAGEZERO, and act accordingly
				hotspot = (RXHotspot*)(inventory_i + 1);
				break;
			}
		}
	}
	
	// if the new current hotspot is valid, matches the mouse down hotspot and the mouse is not dragging, we need to send a mouse up message to the hotspot
	if (hotspot >= (RXHotspot*)0x1000 && hotspot == _mouse_down_hotspot && isinf(mouse_vector.size.width)) {
		// reset the mouse down hotspot
		[_mouse_down_hotspot release];
		_mouse_down_hotspot = nil;
	
		[self disableHotspotHandling];
		[sengine performSelector:@selector(mouseUpInHotspot:) withObject:hotspot inThread:[g_world scriptThread]];
	}
	
	// if the old current hotspot is valid, doesn't match the new current hotspot and is still active, we need to send the old current hotspot a mouse exited message
	if (_currentHotspot >= (RXHotspot*)0x1000 && _currentHotspot != hotspot && [active_hotspots indexOfObjectIdenticalTo:_currentHotspot] != NSNotFound) {
		// note that we DO NOT disable hotspot handling for "exited hotspot" messages
		[sengine performSelector:@selector(mouseExitedHotspot:) withObject:_currentHotspot inThread:[g_world scriptThread]];
	}
	
	// handle cursor changes here so we don't ping-pong across 2 threads (at least for a hotspot's cursor, the inventory item cursor and the default cursor)
	if (hotspot == 0)
		[g_worldView setCursor:[g_world defaultCursor]];
	else if (hotspot < (RXHotspot*)0x1000)
		[g_worldView setCursor:[g_world openHandCursor]];
	else {
		[g_worldView setCursor:[g_world cursorForID:[hotspot cursorID]]];
		
		// valid hotspots receive periodic "inside hotspot" messages when the mouse is not dragging; note that we do NOT disable hotspot handling for "inside hotspot" messages
		if (isinf(mouse_vector.size.width))
			[sengine performSelector:@selector(mouseInsideHotspot:) withObject:hotspot inThread:[g_world scriptThread]];
	}
	
	// update the current hotspot to the new current hotspot
	if (_currentHotspot != hotspot) {
		id old = _currentHotspot;
		
		if (hotspot >= (RXHotspot*)0x1000)
			_currentHotspot = [hotspot retain];
		else
			_currentHotspot = hotspot;
		
		if (old >= (RXHotspot*)0x1000)
			[old release];
	}
	
	OSSpinLockUnlock(&_state_swap_lock);
}

- (void)_handleInventoryMouseDown:(NSEvent*)event inventoryIndex:(uint32_t)index {
	// WARNING: this method assumes the state swap lock has been taken by the caller
	
	if (index >= RX_MAX_INVENTORY_ITEMS)
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"OUT OF BOUNDS INVENTORY INDEX" userInfo:nil];
	
	RXEdition* edition = [[RXEditionManager sharedEditionManager] currentEdition];
	
	NSNumber* journalCardIDNumber = [[edition valueForKey:@"journalCardIDMap"] objectForKey:RX_INVENTORY_KEYS[index]];
	if (!journalCardIDNumber)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"NO CARD ID FOR GIVEN INVENTORY KEY IN JOURNAL CARD ID MAP" userInfo:nil];
	
	// set the return card in the game state to the current card; need to take the render lock to avoid a race condition with the script thread executing a card swap
	[[g_world gameState] setReturnCard:[[_front_render_state->card descriptor] simpleDescriptor]];
	
	// schedule a cross-fade transition to the journal card
	RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionDissolve direction:0 region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
	[self queueTransition:transition];
	[transition release];
	
	// activate an empty sound group with fade out to fade out the current card's ambient sounds
	RXSoundGroup* sgroup = [RXSoundGroup new];
	sgroup->gain = 1.0f;
	sgroup->loop = NO;
	sgroup->fadeOutActiveGroupBeforeActivating = YES;
	sgroup->fadeInOnActivation = NO;
	[self performSelector:@selector(activateSoundGroup:) withObject:sgroup inThread:[g_world scriptThread] waitUntilDone:NO];
	[sgroup release];
	
	// leave ourselves a note to force a fade in on the next activate sound group command
	_forceFadeInOnNextSoundGroup = YES;
	
	// change the active card to the journal card
	[self setActiveCardWithStack:@"aspit" ID:[journalCardIDNumber unsignedShortValue] waitUntilDone:NO];
}

- (void)mouseMoved:(NSEvent*)event {
	NSPoint mousePoint = [(NSView*)g_worldView convertPoint:[event locationInWindow] fromView:nil];
	
	// update the mouse vector
	OSSpinLockLock(&_mouseVectorLock);
	_mouseVector.origin = mousePoint;
	OSSpinLockUnlock(&_mouseVectorLock);
	
	// finally we need to update the hotspot state
	[self updateHotspotState];
}

- (void)mouseDragged:(NSEvent*)event {
	NSPoint mousePoint = [(NSView*)g_worldView convertPoint:[event locationInWindow] fromView:nil];
	
	// update the mouse vector
	OSSpinLockLock(&_mouseVectorLock);
	_mouseVector.size.width = mousePoint.x - _mouseVector.origin.x;
	_mouseVector.size.height = mousePoint.y - _mouseVector.origin.y;
	OSSpinLockUnlock(&_mouseVectorLock);
	
	// finally we need to update the hotspot state
	[self updateHotspotState];
}

- (void)mouseDown:(NSEvent*)event {
	// update the mouse vector
	OSSpinLockLock(&_mouseVectorLock);
	_mouseVector.origin = [(NSView*)g_worldView convertPoint:[event locationInWindow] fromView:nil];
	_mouseVector.size = NSZeroSize;
	OSSpinLockUnlock(&_mouseVectorLock);
	
	// if hotspot handling is disabled, simply return
	if (_hotspot_handling_disable_counter > 0) {
		return;
	}
	
	// cannot use the front card during state swaps
	OSSpinLockLock(&_state_swap_lock);
	
	// if the current hotspot is valid, send it a mouse down event; if the current "hotspot" is an inventory item, handle that too
	if (_currentHotspot >= (RXHotspot*)0x1000) {
		// remember the last hotspot for which we've sent a "mouse down" message
		_mouse_down_hotspot = [_currentHotspot retain];
		
		[self disableHotspotHandling];
		[sengine performSelector:@selector(mouseDownInHotspot:) withObject:_currentHotspot inThread:[g_world scriptThread]];
	} else if (_currentHotspot)
		[self _handleInventoryMouseDown:event inventoryIndex:(uint32_t)_currentHotspot - 1];
	
	OSSpinLockUnlock(&_state_swap_lock);
	
	// we do not need to call updateHotspotState from mouse down, since handling the inventory condition would be difficult there 
	// (can't retain a non-valid pointer value, e.g. can't store the dummy _currentHotspot value into _mouse_down_hotspot
}

- (void)mouseUp:(NSEvent*)event {
	// update the mouse vector
	OSSpinLockLock(&_mouseVectorLock);
	_mouseVector.origin = [(NSView*)g_worldView convertPoint:[event locationInWindow] fromView:nil];
	_mouseVector.size.width = INFINITY;
	_mouseVector.size.height = INFINITY;
	OSSpinLockUnlock(&_mouseVectorLock);
	
	// if hotspot handling is disabled, simply return
	if (_hotspot_handling_disable_counter > 0) {
		return;
	}
	
	// finally we need to update the hotspot state; updateHotspotState will take care of sending the mouse up even if it sees a mouse down hotspot and the mouse is still over the hotspot
	[self updateHotspotState];
}

- (void)_handleWindowDidBecomeKey:(NSNotification*)notification {
	// FIXME: there may be a time-sensitive crash lurking around here

	NSWindow* window = [notification object];
	if (window == [g_worldView window]) {
		// update the mouse vector
		OSSpinLockLock(&_mouseVectorLock);
		
		_mouseVector.origin = [(NSView*)g_worldView convertPoint:[[(NSView*)g_worldView window] mouseLocationOutsideOfEventStream] fromView:nil];
		_mouseVector.size.width = INFINITY;
		_mouseVector.size.height = INFINITY;
		
		OSSpinLockUnlock(&_mouseVectorLock);
		
		// update the hotspot state
		[self updateHotspotState];
	}
}

- (void)_handleWindowDidResignKey:(NSNotification*)notification {

}

@end
