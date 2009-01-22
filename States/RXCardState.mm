//
//	RXCardState.m
//	rivenx
//
//	Created by Jean-Francois Roy on 24/01/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import <OpenGL/CGLMacro.h>
#import <OpenGL/CGLProfilerFunctionEnum.h>
#import <OpenGL/CGLProfiler.h>

#import <GLUT/GLUT.h>

#import <mach/mach.h>
#import <mach/mach_time.h>

#import <MHKKit/MHKAudioDecompression.h>

#import "Base/RXTiming.h"
#import "Engine/RXWorldProtocol.h"

#import "States/RXCardState.h"

#import "Engine/RXHardwareProfiler.h"
#import "Engine/RXHotspot.h"
#import "Engine/RXMovieProxy.h"
#import "Engine/RXEditionManager.h"

#import "Rendering/Audio/RXCardAudioSource.h"
#import "Rendering/Graphics/GL/GLShaderProgramManager.h"

typedef void (*RenderCardImp_t)(id, SEL, const CVTimeStamp*, CGLContextObj);
static RenderCardImp_t _renderCardImp;
static SEL _renderCardSel = @selector(_renderCard:inContext:);

typedef void (*PostFlushCardImp_t)(id, SEL, const CVTimeStamp*);
static PostFlushCardImp_t _postFlushCardImp;
static SEL _postFlushCardSel = @selector(_postFlushCard:);

static rx_render_dispatch_t picture_render_dispatch;
static rx_post_flush_tasks_dispatch_t picture_flush_task_dispatch;

static rx_render_dispatch_t _movieRenderDispatch;
static rx_post_flush_tasks_dispatch_t _movieFlushTasksDispatch;

static const double RX_AUDIO_FADE_DURATION = 2.0;
static const double RX_AUDIO_FADE_DURATION_PLUS_POINT_FIVE = RX_AUDIO_FADE_DURATION + 0.5;

static const GLuint RX_CARD_STATIC_RENDER_INDEX = 0;
static const GLuint RX_CARD_DYNAMIC_RENDER_INDEX = 1;
static const GLuint RX_CARD_PREVIOUS_FRAME_INDEX = 2;

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
	renderer->RampSourceGain(*source, source->NominalGain(), RX_AUDIO_FADE_DURATION);
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
		
		_renderCardImp = (RenderCardImp_t)[self instanceMethodForSelector:_renderCardSel];
		_postFlushCardImp = (PostFlushCardImp_t)[self instanceMethodForSelector:_postFlushCardSel];
		
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
	_front_render_state->movies = [NSMutableArray new];
	
	_back_render_state->pictures = [NSMutableArray new];
	_back_render_state->movies = [NSMutableArray new];
	
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
	
	[self _initializeRendering];
	
	// initialize the mouse vector
	_mouseVector.origin = [(NSView*)g_worldView convertPoint:[[(NSView*)g_worldView window] mouseLocationOutsideOfEventStream] fromView:nil];
	_mouseVector.size.width = INFINITY;
	_mouseVector.size.height = INFINITY;
	
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
	
	if (_render_states_buffer) {
		[_front_render_state->pictures release];
		[_front_render_state->movies release];
		
		[_back_render_state->pictures release];
		[_back_render_state->movies release];
		
		free(_render_states_buffer);
	}
	
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
	glGenFramebuffersEXT(2, _fbos);
	glGenTextures(3, _textures);
	
	// disable client storage because it's incompatible with allocating texture space with NULL (which is what we want to do for FBO color attachement textures) and with the PIXEL_UNPACK buffer
	glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_FALSE);
	
	for (GLuint i = 0; i < 2; i++) {
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
	
	// configure the additional texture (the previous frame texture)
	for (GLuint i = 2; i < 3; i++) {
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
	}
	
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
	glGenBuffers(1, &_inventoryTextureBuffer); glReportError();
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, _inventoryTextureBuffer); glReportError();
	
	// allocate the texture buffer (aligned to 128 bytes)
	inventoryTotalTextureSize = (inventoryTotalTextureSize & ~0x7f) + 0x80;
	glBufferData(GL_PIXEL_UNPACK_BUFFER, inventoryTotalTextureSize, NULL, GL_STATIC_READ); glReportError();
	
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
	glBufferData(GL_ARRAY_BUFFER, 64 * sizeof(GLfloat), NULL, GL_STATIC_DRAW); glReportError();
	
	// map the VBO and write the vertex attributes
	GLfloat* positions = reinterpret_cast<GLfloat*>(glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY)); glReportError();
	GLfloat* tex_coords0 = positions + 2;
	
	// main card composite
	{
		positions[0] = kRXCardViewportOriginOffset.x; positions[1] = kRXCardViewportOriginOffset.y;
		tex_coords0[0] = 0.0f; tex_coords0[1] = 0.0f;
		positions += 4; tex_coords0 += 4;
		
		positions[0] = kRXCardViewportOriginOffset.x + kRXCardViewportSize.width; positions[1] = kRXCardViewportOriginOffset.y;
		tex_coords0[0] = kRXCardViewportSize.width; tex_coords0[1] = 0.0f;
		positions += 4; tex_coords0 += 4;
		
		positions[0] = kRXCardViewportOriginOffset.x; positions[1] = kRXCardViewportOriginOffset.y + kRXCardViewportSize.height;
		tex_coords0[0] = 0.0f; tex_coords0[1] = kRXCardViewportSize.height;
		positions += 4; tex_coords0 += 4;
		
		positions[0] = kRXCardViewportOriginOffset.x + kRXCardViewportSize.width; positions[1] = kRXCardViewportOriginOffset.y + kRXCardViewportSize.height;
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
	glTexCoordPointer(2, GL_FLOAT, 4 * sizeof(GLfloat), BUFFER_OFFSET(NULL, 2 * sizeof(GLfloat))); glReportError();
	
	// card render VAO / VA / VBO
	
	// gen the buffers
	glGenVertexArraysAPPLE(1, &_cardRenderVAO); glReportError();
	glGenBuffers(1, &_cardRenderVBO); glReportError();
	
	// bind them
	[gl_state bindVertexArrayObject:_cardRenderVAO];
	glBindBuffer(GL_ARRAY_BUFFER, _cardRenderVBO); glReportError();
	
	// enable sub-range flushing if available
	if (GLEE_APPLE_flush_buffer_range)
		glBufferParameteriAPPLE(GL_ARRAY_BUFFER, GL_BUFFER_FLUSHING_UNMAP_APPLE, GL_FALSE);
	
	// 4 vertices, [<position.x position.y> <texcoord0.s texcoord0.t>], floats
	glBufferData(GL_ARRAY_BUFFER, 16 * sizeof(GLfloat), NULL, GL_STATIC_DRAW); glReportError();
	
	// map the VBO and write the vertex attributes
	positions = reinterpret_cast<GLfloat*>(glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY)); glReportError();
	tex_coords0 = positions + 2;
	
	positions[0] = 0.0f; positions[1] = 0.0f;
	tex_coords0[0] = 0.0f; tex_coords0[1] = 0.0f;
	positions += 2; tex_coords0 += 2;
	
	positions[2] = kRXCardViewportSize.width; positions[3] = 0.0f;
	tex_coords0[2] = kRXCardViewportSize.width; tex_coords0[3] = 0.0f;
	positions += 2; tex_coords0 += 2;
	
	positions[4] = 0.0f; positions[5] = kRXCardViewportSize.height;
	tex_coords0[4] = 0.0f; tex_coords0[5] = kRXCardViewportSize.height;
	positions += 2; tex_coords0 += 2;
	
	positions[6] = kRXCardViewportSize.width; positions[7] = kRXCardViewportSize.height;
	tex_coords0[6] = kRXCardViewportSize.width; tex_coords0[7] = kRXCardViewportSize.height;
	
	// unmap and flush the card render buffer
	if (GLEE_APPLE_flush_buffer_range)
		glFlushMappedBufferRangeAPPLE(GL_ARRAY_BUFFER, 0, 16 * sizeof(GLfloat));
	glUnmapBuffer(GL_ARRAY_BUFFER); glReportError();
	
	// configure the VAs
	glEnableClientState(GL_VERTEX_ARRAY); glReportError();
	glVertexPointer(2, GL_FLOAT, 4 * sizeof(GLfloat), BUFFER_OFFSET(NULL, 0)); glReportError();
	
	glClientActiveTexture(GL_TEXTURE0);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
	glTexCoordPointer(2, GL_FLOAT, 4 * sizeof(GLfloat), BUFFER_OFFSET(NULL, 2 * sizeof(GLfloat))); glReportError();
	
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
	glBufferData(GL_ARRAY_BUFFER, (RX_MAX_RENDER_HOTSPOT + RX_MAX_INVENTORY_ITEMS) * 24 * sizeof(GLfloat), NULL, GL_DYNAMIC_DRAW); glReportError();
	
	// configure the VAs
	glEnableClientState(GL_VERTEX_ARRAY); glReportError();
	glVertexPointer(2, GL_FLOAT, 6 * sizeof(GLfloat), NULL); glReportError();
	
	glEnableClientState(GL_COLOR_ARRAY); glReportError();
	glColorPointer(4, GL_FLOAT, 6 * sizeof(GLfloat), BUFFER_OFFSET(NULL, 2 * sizeof(GLfloat))); glReportError();
	
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
	while ((sound = [soundEnum nextObject])) if (sound->detachTimestampValid && RXTimingTimestampDelta(now, sound->rampStartTimestamp) >= RX_AUDIO_FADE_DURATION_PLUS_POINT_FIVE) [soundsToRemove addObject:sound];
	
	soundEnum = [_activeDataSounds objectEnumerator];
	while ((sound = [soundEnum nextObject])) if (sound->detachTimestampValid && RXTimingTimestampDelta(now, sound->rampStartTimestamp) >= sound->source->Duration() + 0.5) [soundsToRemove addObject:sound];
	
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
#if defined(DEBUG)
	else RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"updated active sources by removing %@", soundsToRemove);
#endif
	
	// remove the sources for all expired sounds from the sound to source map and prepare the detach and delete array
	if (!_sourcesToDelete) _sourcesToDelete = [self _createSourceArrayFromSoundSet:soundsToRemove callbacks:&g_deleteOnReleaseAudioSourceArrayCallbacks];
	
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
	RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"activating sound group %@ with sounds: %@", soundGroup, soundGroupSounds);
#endif
	
	// create an array of new sources
	CFMutableArrayRef sourcesToAdd = CFArrayCreateMutable(NULL, 0, &g_weakAudioSourceArrayCallbacks);
	
	// compute a new active sound set
	NSMutableSet* oldActiveSounds = _activeSounds;
	NSMutableSet* newActiveSounds = [_activeSounds mutableCopy];
	
	// compute the set of sounds to remove
	NSMutableSet* soundsToRemove = [_activeSounds mutableCopy];
	[soundsToRemove minusSet:soundGroupSounds];
	
	// process new and updated sounds
	NSEnumerator* soundEnum = [soundGroupSounds objectEnumerator];
	RXSound* sound;
	while ((sound = [soundEnum nextObject])) {
		RXSound* oldSound = [_activeSounds member:sound];
		if (!oldSound) {
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
		} else {
			// UPDATE SOUND
			assert(oldSound->source);
			
			// update gain and pan
			oldSound->gain = sound->gain;
			oldSound->pan = sound->pan;
			
			// make sure the sound doesn't have a valid detach timestamp
			oldSound->detachTimestampValid = NO;
			
			// looping
			oldSound->source->SetLooping(soundGroup->loop);
			
			// FIXME: pan ramp
			renderer->SetSourcePan(*(oldSound->source), sound->pan);
			
			// gain; always use a ramp to prevent disrupting an ongoing ramp up
			renderer->RampSourceGain(*(oldSound->source), oldSound->gain * soundGroup->gain, RX_AUDIO_FADE_DURATION);
			oldSound->source->SetNominalGain(oldSound->gain * soundGroup->gain);
		}
	}
	
	// one round of tasking for new sources so that there's data ready immediately
	CFRange everything = CFRangeMake(0, CFArrayGetCount(sourcesToAdd));
	CFArrayApplyFunction(sourcesToAdd, everything, RXCardAudioSourceTaskApplier, renderer);
	
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
	_activeSounds = newActiveSounds;
	[oldActiveSounds release];
	
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
	
	// ramps are go!
	// FIXME: scheduling ramps in this manner is not atomic
	if (soundGroup->fadeInOnActivation || _forceFadeInOnNextSoundGroup) {
		CFRange everything = CFRangeMake(0, CFArrayGetCount(sourcesToAdd));
		CFArrayApplyFunction(sourcesToAdd, everything, RXCardAudioSourceEnableApplier, [g_world audioRenderer]);
	}
	
	if (soundGroup->fadeOutActiveGroupBeforeActivating) {
		CFMutableArrayRef sourcesToRemove = [self _createSourceArrayFromSoundSet:soundsToRemove callbacks:&g_weakAudioSourceArrayCallbacks];
		renderer->RampSourcesGain(sourcesToRemove, 0.0f, RX_AUDIO_FADE_DURATION);
		CFRelease(sourcesToRemove);
		
		uint64_t now = RXTimingNow();
		NSEnumerator* soundEnum = [soundsToRemove objectEnumerator];
		RXSound* sound;
		while ((sound = [soundEnum nextObject])) {
			sound->rampStartTimestamp = now;
			sound->detachTimestampValid = YES;
		}
	}
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"activateSoundGroup: _activeSounds = %@", _activeSounds);
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
	
	// one round of tasking so that there's data ready immediately
	sound->source->RenderTask();
	
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
	NSAutoreleasePool* p = [[NSAutoreleasePool alloc] init];
	
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
		
		// sleep until the next task cycle
		usleep(400000U);
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
	
	uint32_t index = [_front_render_state->movies indexOfObject:movie];
	if (index != NSNotFound)
		[_front_render_state->movies removeObjectAtIndex:index];
	
	[_front_render_state->movies addObject:movie];
	
	if (index == NSNotFound)
		[[movie owner] retain];
	
	OSSpinLockUnlock(&_renderLock);
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"enabled movie %@, back movie list count at %d", movie, [_front_render_state->movies count]);
#endif
}


- (void)disableMovie:(RXMovie*)movie {
	OSSpinLockLock(&_renderLock);
	
	uint32_t index = [_front_render_state->movies indexOfObject:movie];
	if (index != NSNotFound) {
		[[movie movie] stop];
		[[movie owner] release];
		[_front_render_state->movies removeObjectAtIndex:index];
	}
	
	OSSpinLockUnlock(&_renderLock);
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"disabled movie %@, back movie list count at %d", movie, [_front_render_state->movies count]);
#endif
}

- (void)disableAllMovies {
	OSSpinLockLock(&_renderLock);
	
	NSEnumerator* movie_enum = [_front_render_state->movies objectEnumerator];
	RXMovie* movie;
	while ((movie = [movie_enum nextObject]))
		[[movie movie] stop];
	CFArrayApplyFunction((CFArrayRef)_front_render_state->movies, CFRangeMake(0, [_front_render_state->movies count]), rx_release_owner_applier, self);
	[_front_render_state->movies removeAllObjects];
	
	OSSpinLockUnlock(&_renderLock);
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"disabled all movies, back movie list count at %d", [_front_render_state->movies count]);
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

- (void)swapRenderState:(RXCard*)sender {	
	// if we'll queue a transition, mark script execution as being blocked now
	if ([_transitionQueue count] > 0)
		[self setExecutingBlockingAction:YES];
	
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
	
	NSMutableArray* new_movies = _back_render_state->movies;
	_back_render_state->movies = _front_render_state->movies;
	_front_render_state->movies = new_movies;
	
	// fast swap
	_front_render_state = _back_render_state;
	
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
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"swapped render state, front card=%@", _front_render_state->card);
#endif
	
	// if the front card has changed, we need to run the new card's "start rendering" program
	if (_front_render_state->new_card) {
		// reclaim the back render state's card
		[_back_render_state->card release];
		_back_render_state->card = _front_render_state->card;
		
		// run the new front card's "start rendering" script
		[_front_render_state->card startRendering];
		
		// the card switch is done; we're no longer blocking script execution
		[self setExecutingBlockingAction:NO];
	}
}

#pragma mark -
#pragma mark card switching

- (void)_postCardSwitchNotification:(RXCard*)newCard {
	// WARNING: MUST RUN ON THE MAIN THREAD
	[[NSNotificationCenter defaultCenter] postNotificationName:@"RXActiveCardDidChange" object:newCard];
}

- (void)_switchCardWithSimpleDescriptor:(RXSimpleCardDescriptor*)simpleDescriptor {
	// WARNING: MUST RUN ON THE SCRIPT THREAD
	if ([NSThread currentThread] != [g_world scriptThread])
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_switchCardWithSimpleDescriptor: MUST RUN ON SCRIPT THREAD" userInfo:nil];
	
	RXCard* newCard = nil;
	
	// if we're switching to the same card, don't allocate another copy of it
	if (_front_render_state->card) {
		RXCardDescriptor* activeDescriptor = [_front_render_state->card descriptor];
		RXStack* activeStack = [activeDescriptor valueForKey:@"parent"];
		NSNumber* activeID = [activeDescriptor valueForKey:@"ID"];
		if ([[activeStack key] isEqualToString:simpleDescriptor->parentName] && simpleDescriptor->cardID == [activeID unsignedShortValue]) {
			newCard = [_front_render_state->card retain];
#if (DEBUG)
			RXOLog(@"reloading front card: %@", _front_render_state->card);
#endif
		}
	}
	
	// if we're switching to a different card, create it
	if (newCard == nil) {
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
		
		newCard = [[RXCard alloc] initWithCardDescriptor:newCardDescriptor];
		[newCardDescriptor release];
		
		// set ourselves as the Riven script handler
		[newCard setRivenScriptHandler:self];
		
#if (DEBUG)
		RXOLog(@"switch card: {from=%@, to=%@}", _front_render_state->card, newCard);
#endif
	}
	
	// switching card blocks script execution
	[self setExecutingBlockingAction:YES];
	
	// changing card completely invalidates the hotspot state, so we also nuke the current hotspot
	[self resetHotspotState];
	_currentHotspot = nil;
	
	// setup the back render state
	_back_render_state->card = [newCard retain];
	_back_render_state->new_card = YES;
	_back_render_state->transition = nil;
	
	// run the stop rendering script on the old card
	[_front_render_state->card stopRendering];
	
	// we have to update the current card in the game state now, otherwise refresh card commands in the prepare for rendering script will jump back to the old card
	[[g_world gameState] setCurrentCard:[[_back_render_state->card descriptor] simpleDescriptor]];
	
	// run the prepare for rendering script on the new card
	[_back_render_state->card prepareForRendering];
	
	// notify that the front card has changed
	[self performSelectorOnMainThread:@selector(_postCardSwitchNotification:) withObject:newCard waitUntilDone:NO];
	[newCard release];
}

- (void)_clearActiveCard {
	// WARNING: MUST RUN ON THE SCRIPT THREAD
	if ([NSThread currentThread] != [g_world scriptThread])
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_clearActiveCard: MUST RUN ON SCRIPT THREAD" userInfo:nil];
	
	// switching card blocks script execution
	[self setExecutingBlockingAction:YES];
	
	// changing card completely invalidates the hotspot state, so we also nuke the current hotspot
	[self resetHotspotState];
	_currentHotspot = nil;
	
	// setup the back render state
	_back_render_state->card = nil;
	_back_render_state->new_card = YES;
	_back_render_state->transition = nil;
	
	// run the stop rendering script on the old card
	[_front_render_state->card stopRendering];
	
	// wipe out the transition queue
	[_transitionQueue removeAllObjects];
	
	// fake a swap render state
	[self swapRenderState:_front_render_state->card];
	
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

- (void)_renderCard:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	
	// read the front render state pointer once and alias it for this method
	struct rx_card_state_render_state* r = _front_render_state;
	
	// alias the global render context state object
	NSObject<RXOpenGLStateProtocol>* gl_state = g_renderContextState;
	
	// render object enumeration variables
	NSEnumerator* renderListEnumerator;
	id<RXRenderingProtocol> renderObject;
	
	// render static card pictures only when necessary
	if (r->refresh_static) {
		GLuint refresh_fbo;
		if (r->water_fx.sfxe)
			refresh_fbo = _fbos[RX_CARD_STATIC_RENDER_INDEX];
		else
			refresh_fbo = _fbos[RX_CARD_DYNAMIC_RENDER_INDEX];
		glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, refresh_fbo); glReportError();
		
		// use the rect texture program
		glUseProgram(_single_rect_texture_program); glReportError();
		
		// render each picture
		renderListEnumerator = [r->pictures objectEnumerator];
		while ((renderObject = [renderListEnumerator nextObject]))
			[renderObject render:outputTime inContext:cgl_ctx framebuffer:refresh_fbo];
		
		// if we have an active water special effect, we must reset it to frame 0 and copy the new static content into the "previous frame" texture if we changed the static content (e.g. new pictures)
		if (r->water_fx.sfxe && [r->pictures count]) {
			r->water_fx.current_frame = 0;
			r->water_fx.frame_timestamp = 0;
			
			// copy the frame into the previous frame texture; texture0 should be the active texture image unit at this point
			glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _textures[RX_CARD_PREVIOUS_FRAME_INDEX]); glReportError();
			glCopyTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, 0, 0, 0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height); glReportError();
		}
	}
	
	// bind the dynamic render FBO
	if (r->water_fx.sfxe || !r->refresh_static) {
		glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _fbos[RX_CARD_DYNAMIC_RENDER_INDEX]); glReportError();
	}
	
	// water effect phase 1
	if (r->water_fx.sfxe) {		
		// setup the texture image units
		glActiveTexture(GL_TEXTURE2); glReportError();
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _textures[RX_CARD_PREVIOUS_FRAME_INDEX]);
		glReportError();
			
		glActiveTexture(GL_TEXTURE1); glReportError();
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, r->water_fx.sfxe->frames[r->water_fx.current_frame]); glReportError();
		
		glActiveTexture(GL_TEXTURE0); glReportError();
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _textures[RX_CARD_STATIC_RENDER_INDEX]); glReportError();
		
		// bind the card render VAO
		[gl_state bindVertexArrayObject:_cardRenderVAO];
		
		// draw the water effect
		glUseProgram(_waterProgram); glReportError();
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); glReportError();
		
		// switch back to the single rect texture program
		glUseProgram(_single_rect_texture_program); glReportError();
	} else if (!r->refresh_static) {
		// use the rect texture program
		glUseProgram(_single_rect_texture_program); glReportError();
	}
		
	// render movies; they will either be rendered into the static content texure or the dynamic content texture prior to that texture being readback into the previous frame texture for water animation
	renderListEnumerator = [r->movies objectEnumerator];
	while ((renderObject = [renderListEnumerator nextObject]))
		_movieRenderDispatch.imp(renderObject, _movieRenderDispatch.sel, outputTime, cgl_ctx, _fbos[RX_CARD_DYNAMIC_RENDER_INDEX]);
	
	// water animation phase 2; if we do not have an active water animation effect, simply blit the static content framebuffer to the dynamic content framebuffer
	if (r->water_fx.sfxe) {
		// copy the frame into the previous frame texture
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _textures[RX_CARD_PREVIOUS_FRAME_INDEX]); glReportError();
		glCopyTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, 0, 0, 0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height); glReportError();
		
		// if the render timestamp of the frame is 0, set it to now
		if (r->water_fx.frame_timestamp == 0)
			r->water_fx.frame_timestamp = outputTime->hostTime;
		
		// if the frame has expired its duration, move to the next frame
		double delta = RXTimingTimestampDelta(outputTime->hostTime, r->water_fx.frame_timestamp);
		if (delta >= (1.0 / r->water_fx.sfxe->fps)) {
			r->water_fx.current_frame = (r->water_fx.current_frame + 1) % r->water_fx.sfxe->nframes;
			r->water_fx.frame_timestamp = 0;
		}
	}
	
	// any static content has been refreshed at the end of this method
	r->refresh_static = NO;
}

- (void)_postFlushCard:(const CVTimeStamp*)outputTime {
	NSEnumerator* e = [_front_render_state->movies objectEnumerator];
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
	_renderCardImp(self, _renderCardSel, outputTime, cgl_ctx);
	
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
			
			// mark script execution as being unblocked
			[self setExecutingBlockingAction:NO];
			
			// signal we're no longer running a transition
			semaphore_signal_all(_transitionSemaphore);
			
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
			if (transition->margin_uniform != -1) {
				GLfloat margin;
				switch (_front_render_state->transition->direction) {
					case RXTransitionLeft:
					case RXTransitionRight:
						margin = kRXCardViewportOriginOffset.x;
						break;
					case RXTransitionTop:
					case RXTransitionBottom:
						margin = kRXCardViewportOriginOffset.y;
						break;
				}
				
				glUniform1f(transition->margin_uniform, margin); glReportError();
			}
			
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
	
	// render hotspots
	if (RXEngineGetBool(@"rendering.renderHotspots")) {
		NSArray* activeHotspots = [_front_render_state->card activeHotspots];
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
	
	if (RXEngineGetBool(@"rendering.mouse_info")) {
		char mouse_info[100];
		NSRect mouse = [self mouseVector];
		snprintf(mouse_info, 100, "mouse vector: (%f, %f) (%f, %f)", mouse.origin.x, mouse.origin.y, mouse.size.width, mouse.size.height);
		
		GLfloat background_strip[] = {
			9.5f, 19.5f, 0.0f,
			9.5f + glutBitmapLength(GLUT_BITMAP_8_BY_13, (unsigned char *)mouse_info), 19.5f, 0.0f,
			9.5f, 19.5f + 13.0f, 0.0f,
			9.5f + glutBitmapLength(GLUT_BITMAP_8_BY_13, (unsigned char *)mouse_info), 19.5f + 13.0f, 0.0f
		};
		
		[gl_state bindVertexArrayObject:0];
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		glVertexPointer(3, GL_FLOAT, 0, background_strip);
		glEnableClientState(GL_VERTEX_ARRAY);
		
		glColor4f(0.0f, 0.0f, 0.0f, 1.0f);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		
		glDisableClientState(GL_VERTEX_ARRAY);
		
		glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
		glRasterPos3d(10.5f, 20.5f, 0.0f);
		size_t l = strlen(mouse_info);
		for (size_t i = 0; i < l; i++)
			glutBitmapCharacter(GLUT_BITMAP_8_BY_13, mouse_info[i]);
	}
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	OSSpinLockLock(&_renderLock);
	
	// we need an inner pool within the scope of that lock, or we run the risk of autoreleased enumerators causing objects that should be deallocated on the main thread not to be
	NSAutoreleasePool* p = [NSAutoreleasePool new];
	
	// do nothing if there is no front card
	if (!_front_render_state->card)
		goto exit_flush_tasks;
	
	_postFlushCardImp(self, _postFlushCardSel, outputTime);
	
exit_flush_tasks:
	[p release];
	OSSpinLockUnlock(&_renderLock);
}

#pragma mark -
#pragma mark user event handling

- (void)_updateCursorVisibility {
	// WARNING: MUST RUN ON THE MAIN THREAD
	if (!pthread_main_np()) {
		[self performSelectorOnMainThread:@selector(_updateCursorVisibility) withObject:nil waitUntilDone:NO];
		return;
	}
	
	// if script execution is blocked, we hide the cursor by setting it to the invisible cursor (we don't want to hide the cursor system-wide, just over the game viewport)
	if (_scriptExecutionBlockedCounter > 0) {
		_cursorBackup = [g_worldView cursor];
		[g_worldView setCursor:[g_world cursorForID:9000]];
		
		// disable saving
		[[NSApp delegate] setValue:[NSNumber numberWithBool:NO] forKey:@"savingEnabled"];
		
	// otherwise if the hotspot state has not been reset, we restore the previous cursor
	} else {
		if (!_resetHotspotState) {
#if defined(DEBUG)
			RXOLog2(kRXLoggingEvents, kRXLoggingLevelDebug, @"resetting cursor to previous cursor");
#endif
			[g_worldView setCursor:_cursorBackup];
		}
		
		// enable saving
		[[NSApp delegate] setValue:[NSNumber numberWithBool:YES] forKey:@"savingEnabled"];
	}
}

- (void)setProcessUIEvents:(BOOL)process {
	if (process) {
		assert(_ignoreUIEventsCounter > 0);
		OSAtomicDecrement32Barrier(&_ignoreUIEventsCounter);
#if defined(DEBUG) && DEBUG > 1
	RXOLog2(kRXLoggingEvents, kRXLoggingLevelDebug, @"UI events ignore counter decreased to %u ", _ignoreUIEventsCounter);
#endif
		
		// if the count falls to 0, refresh hotspots by faking a mouseMoved event
		if (_ignoreUIEventsCounter == 0 && _resetHotspotState) {
			NSEvent* mouseEvent = [NSEvent mouseEventWithType:NSMouseMoved 
													 location:[[g_worldView window] mouseLocationOutsideOfEventStream] 
												modifierFlags:0 
													timestamp:[[NSApp currentEvent] timestamp] 
												 windowNumber:[[g_worldView window] windowNumber] 
													  context:[[g_worldView window] graphicsContext] 
												  eventNumber:0 
												   clickCount:0 
													 pressure:0.0f];
			[[g_worldView window] postEvent:mouseEvent atStart:YES];
		}
	} else {
		assert(_ignoreUIEventsCounter < INT32_MAX);
		OSAtomicIncrement32Barrier(&_ignoreUIEventsCounter);
#if defined(DEBUG) && DEBUG > 1
	RXOLog2(kRXLoggingEvents, kRXLoggingLevelDebug, @"UI events ignore counter increased to %u ", _ignoreUIEventsCounter);
#endif
	}
}

- (void)setExecutingBlockingAction:(BOOL)blocking {
	if (blocking) {
		assert(_scriptExecutionBlockedCounter < INT32_MAX);
		OSAtomicIncrement32Barrier(&_scriptExecutionBlockedCounter);
		
		if (_scriptExecutionBlockedCounter == 1) {
			// when the script thread is executing a blocking action, we implicitly ignore UI events
			[self setProcessUIEvents:NO];
			
			// update the cursor visibility (hide it)
			[self _updateCursorVisibility];
		}
	} else {
		assert(_scriptExecutionBlockedCounter > 0);
		OSAtomicDecrement32Barrier(&_scriptExecutionBlockedCounter);
		
		if (_scriptExecutionBlockedCounter == 0) {
			// update the cursor visibility (show the previous cursor if the cursor state has not been reset); do this before enabling UI processing so the cursor visibility update is queued on the main thread before the mouse moved event
			[self _updateCursorVisibility];
			
			// re-enable UI event processing; this will take care of updating the cursor if the hotspot state has been reset
			[self setProcessUIEvents:YES];
		}
	}
}

- (void)resetHotspotState {
	// this method is called when switching card and when changing the set of active hotspots from a script
	
	// setting this to yes will cause a mouse moved even to be synthesized the next time the ignore UI events counter reaches 0
	_resetHotspotState = YES;
	
	// note that we do not set the current hotspot to nil in this method, because if may be called within the scope of a particular card, 
	// meaning even though we changed the active set of hotspots, the one we're on may still be valid after
}

- (NSRect)mouseVector {
	OSSpinLockLock(&_mouseVectorLock);
	NSRect r = _mouseVector;
	OSSpinLockUnlock(&_mouseVectorLock);
	return r;
}

- (void)_handleInventoryMouseDown:(NSEvent*)event inventoryIndex:(uint32_t)index {
	if (index >= RX_MAX_INVENTORY_ITEMS)
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"OUT OF BOUNDS INVENTORY INDEX" userInfo:nil];
	
	RXEdition* edition = [[RXEditionManager sharedEditionManager] currentEdition];
	
	NSNumber* journalCardIDNumber = [[edition valueForKey:@"journalCardIDMap"] objectForKey:RX_INVENTORY_KEYS[index]];
	if (!journalCardIDNumber)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"NO CARD ID FOR GIVEN INVENTORY KEY IN JOURNAL CARD ID MAP" userInfo:nil];
	
	// set the return card in the game state to the current card
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

- (void)_trackMouse:(NSEvent*)event {
	NSPoint mousePoint = [(NSView*)g_worldView convertPoint:[event locationInWindow] fromView:nil];
	
	// if the mouse is below the game viewport, bring up the alpha of the inventory to 1; otherwise set it to 0.5
	if (NSPointInRect(mousePoint, [(NSView*)g_worldView bounds]) && mousePoint.y < kRXCardViewportOriginOffset.y)
		_inventoryAlphaFactor = 1.f;
	else
		_inventoryAlphaFactor = 0.5f;
	
#if defined(DEBUG) && DEBUG > 2
	RXOLog2(kRXLoggingEvents, kRXLoggingLevelDebug, @"tracking mouse: position=%@, dragging=%s", NSStringFromPoint(mousePoint), (_isDraggingMouse) ? "YES" : "NO");
#endif
	
	// update the mouse vector
	OSSpinLockLock(&_mouseVectorLock);
	if (_isDraggingMouse) {
		_mouseVector.size.width = mousePoint.x - _mouseVector.origin.x;
		_mouseVector.size.height = mousePoint.y - _mouseVector.origin.y;
	} else
		_mouseVector.origin = mousePoint;
	OSSpinLockUnlock(&_mouseVectorLock);
	
	// if UI events are being ignored, we're done
	if (_ignoreUIEventsCounter > 0)
		return;
	
	// find over which hotspot the mouse is
	NSEnumerator* hotpotEnum = [[_front_render_state->card activeHotspots] objectEnumerator];
	RXHotspot* hotspot;
	while ((hotspot = [hotpotEnum nextObject])) {
		if (NSPointInRect(mousePoint, [hotspot worldViewFrame]))
			break;
	}
	
	// now check if we're over one of the inventory regions
	if (!hotspot) {
		for (GLuint inventory_i = 0; inventory_i < _inventoryItemCount; inventory_i++) {
			if (NSPointInRect(mousePoint, _inventoryHotspotRegions[inventory_i])) {
				// set hotspot to the inventory item index (plus one to avoid the value 0); the following block of code will check if hotspot is not 0 and below PAGEZERO, and act accordingly
				hotspot = (RXHotspot*)(inventory_i + 1);
				break;
			}
		}
	}
	
	// if we are over a different hotspot than the current hotspot, we need to send a mouse exited event followed by a mouse entered event to the old current hotspot and new current hotspot, respectively; we only do this if the mouse is not being dragged
	if ((_currentHotspot != hotspot || _resetHotspotState) && !_isDraggingMouse) {
		// mouseExitedHotspot does not accept nil (we can't exit the "nil" hotspot); also make sure _currentHotspot is not in PAGEZERO (e.g. that it is a valid object)
		if (_currentHotspot >= (RXHotspot*)0x1000)
			[_front_render_state->card performSelector:@selector(mouseExitedHotspot:) withObject:_currentHotspot inThread:[g_world scriptThread]];
		
		// handle cursor changes here so we don't ping-pong across 2 threads (at least for a hotspot's cursor, the inventory item cursor and the default cursor)
		if (hotspot == 0)
			[g_worldView setCursor:[g_world defaultCursor]];
		else if (hotspot < (RXHotspot*)0x1000)
			[g_worldView setCursor:[g_world openHandCursor]];
		else {
			[g_worldView setCursor:[g_world cursorForID:[hotspot cursorID]]];
			[_front_render_state->card performSelector:@selector(mouseEnteredHotspot:) withObject:hotspot inThread:[g_world scriptThread]];
		}
		
		// update the current hotspot to the new current hotspot and indicate the hotspot state has been reset
		_currentHotspot = hotspot;
		_resetHotspotState = NO;
	}
}

- (void)mouseMoved:(NSEvent*)event {
	_isDraggingMouse = NO;
	[self _trackMouse:event];
}

- (void)mouseDragged:(NSEvent*)event {
	_isDraggingMouse = YES;
	[self _trackMouse:event];
}

- (void)mouseDown:(NSEvent*)event {
	// update the mouse vector
	OSSpinLockLock(&_mouseVectorLock);
	_mouseVector.origin = [(NSView*)g_worldView convertPoint:[event locationInWindow] fromView:nil];
	_mouseVector.size = NSZeroSize;
	OSSpinLockUnlock(&_mouseVectorLock);
	
	
	if (_ignoreUIEventsCounter > 0)
		return;
	
	if (_currentHotspot >= (RXHotspot*)0x1000)
		[_front_render_state->card performSelector:@selector(mouseDownInHotspot:) withObject:_currentHotspot inThread:[g_world scriptThread]];
	else if (_currentHotspot)
		[self _handleInventoryMouseDown:event inventoryIndex:(uint32_t)_currentHotspot - 1];
}

- (void)mouseUp:(NSEvent*)event {
	// update the mouse vector
	OSSpinLockLock(&_mouseVectorLock);
	_mouseVector.origin = [(NSView*)g_worldView convertPoint:[event locationInWindow] fromView:nil];
	_mouseVector.size.width = INFINITY;
	_mouseVector.size.height = INFINITY;
	OSSpinLockUnlock(&_mouseVectorLock);

	if (_ignoreUIEventsCounter > 0)
		return;
	
	if (_currentHotspot >= (RXHotspot*)0x1000)
		[_front_render_state->card performSelector:@selector(mouseUpInHotspot:) withObject:_currentHotspot inThread:[g_world scriptThread]];
}

@end
