//
//  RXCardState.m
//  rivenx
//
//  Created by Jean-Francois Roy on 24/01/2006.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import <MHKKit/MHKAudioDecompression.h>

#import "States/RXCardState.h"

#import "Base/RXThreadUtilities.h"

#import "Engine/RXWorldProtocol.h"
#import "Engine/RXHardwareProfiler.h"
#import "Engine/RXHotspot.h"
#import "Engine/RXArchiveManager.h"

#import "Rendering/Audio/RXCardAudioSource.h"
#import "Rendering/Audio/PublicUtility/CAMath.h"
#import "Rendering/Graphics/GL/GLShaderProgramManager.h"
#import "Rendering/Graphics/RXMovieProxy.h"

#import "Application/RXApplicationDelegate.h"

#import "Utilities/auto_spinlock.h"

#if defined(DEBUG)
#import <GLUT/glut.h>
#endif

static rx_render_dispatch_t picture_render_dispatch;
static rx_post_flush_tasks_dispatch_t picture_flush_task_dispatch;

static rx_render_dispatch_t _movieRenderDispatch;
static rx_post_flush_tasks_dispatch_t _movieFlushTasksDispatch;

static const double RX_AUDIO_GAIN_RAMP_DURATION = 2.0;
static const double RX_AUDIO_PAN_RAMP_DURATION = 0.5;

static const unsigned int RX_CARD_DYNAMIC_RENDER_INDEX = 0;

static const unsigned int RX_MAX_RENDER_HOTSPOT = 30;

static const unsigned int RX_MAX_INVENTORY_ITEMS = 3;
static const unsigned int RX_INVENTORY_RMAPS[3] = {5708, 7544, 7880};
static const NSString* RX_INVENTORY_KEYS[3] = {@"Atrus", @"Catherine", @"Prison"};
static const unsigned int RX_INVENTORY_ATRUS = 0;
static const unsigned int RX_INVENTORY_CATHERINE = 1;
static const unsigned int RX_INVENTORY_TRAP = 2;

static const float RX_INVENTORY_MARGIN = 20.f;
static const float RX_INVENTORY_UNFOCUSED_ALPHA = 0.75f;

static const double RX_CREDITS_FADE_DURATION = 1.5;
static const double RX_CREDITS_STILL_DURATION = 5.0;
static const double RX_CREDITS_SCROLLING_DURATION = 20.5;

#pragma mark -
#pragma mark audio source array callbacks

static const void* RXCardAudioSourceArrayWeakRetain(CFAllocatorRef allocator, const void* value) { return value; }

static void RXCardAudioSourceArrayWeakRelease(CFAllocatorRef allocator, const void* value) {}

static void RXCardAudioSourceArrayDeleteRelease(CFAllocatorRef allocator, const void* value)
{ delete const_cast<RX::CardAudioSource*>(reinterpret_cast<const RX::CardAudioSource*>(value)); }

static CFStringRef RXCardAudioSourceArrayDescription(const void* value)
{ return CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::CardAudioSource: %p>"), value); }

static Boolean RXCardAudioSourceArrayEqual(const void* value1, const void* value2) { return value1 == value2; }

static CFArrayCallBacks g_weakAudioSourceArrayCallbacks = {
    0, RXCardAudioSourceArrayWeakRetain, RXCardAudioSourceArrayWeakRelease, RXCardAudioSourceArrayDescription, RXCardAudioSourceArrayEqual};

static CFArrayCallBacks g_deleteOnReleaseAudioSourceArrayCallbacks = {
    0, RXCardAudioSourceArrayWeakRetain, RXCardAudioSourceArrayDeleteRelease, RXCardAudioSourceArrayDescription, RXCardAudioSourceArrayEqual};

#pragma mark -
#pragma mark audio array applier functions

static void RXCardAudioSourceFadeInApplier(const void* value, void* context)
{
  RX::AudioRenderer* renderer = reinterpret_cast<RX::AudioRenderer*>(context);
  RX::CardAudioSource* source = const_cast<RX::CardAudioSource*>(reinterpret_cast<const RX::CardAudioSource*>(value));
  renderer->SetSourceGain(*source, 0.0f);
  renderer->RampSourceGain(*source, source->NominalGain(), RX_AUDIO_GAIN_RAMP_DURATION);
}

static void RXCardAudioSourceEnableApplier(const void* value, void* context)
{
  RX::CardAudioSource* source = const_cast<RX::CardAudioSource*>(reinterpret_cast<const RX::CardAudioSource*>(value));
  source->SetEnabled(true);
}

static void RXCardAudioSourceDisableApplier(const void* value, void* context)
{
  RX::CardAudioSource* source = const_cast<RX::CardAudioSource*>(reinterpret_cast<const RX::CardAudioSource*>(value));
  source->SetEnabled(false);
}

static void RXCardAudioSourceTaskApplier(const void* value, void* context)
{
  RX::CardAudioSource* source = const_cast<RX::CardAudioSource*>(reinterpret_cast<const RX::CardAudioSource*>(value));
  source->RenderTask();
}

#pragma mark -
#pragma mark render object release - owner array applier function

static void rx_release_owner_applier(const void* value, void* context) { [[(id)value owner] release]; }

#pragma mark -

@interface RXCardState (RXCardStatePrivate)
- (void)_initializeRendering;
- (void)_updateActiveSources;
- (void)_clearActiveCard;
- (void)_renderCardWithTimestamp:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx;
- (void)_postFlushCard:(const CVTimeStamp*)outputTime;
@end

typedef void (*RenderCardImp_t)(id, SEL, const CVTimeStamp*, CGLContextObj);
static RenderCardImp_t render_card_imp;
static SEL render_card_sel = @selector(_renderCardWithTimestamp:inContext:);

typedef void (*PostFlushCardImp_t)(id, SEL, const CVTimeStamp*);
static PostFlushCardImp_t post_flush_card_imp;
static SEL post_flush_card_sel = @selector(_postFlushCard:);

@implementation RXCardState

+ (void)initialize
{
  static BOOL initialized = NO;
  if (!initialized) {
    initialized = YES;

    render_card_imp = (RenderCardImp_t)[self instanceMethodForSelector : render_card_sel];
    post_flush_card_imp = (PostFlushCardImp_t)[self instanceMethodForSelector : post_flush_card_sel];

    picture_render_dispatch = RXGetRenderImplementation([RXPicture class], RXRenderingRenderSelector);
    picture_flush_task_dispatch = RXGetPostFlushTasksImplementation([RXPicture class], RXRenderingPostFlushTasksSelector);

    _movieRenderDispatch = RXGetRenderImplementation([RXMovieProxy class], RXRenderingRenderSelector);
    _movieFlushTasksDispatch = RXGetPostFlushTasksImplementation([RXMovieProxy class], RXRenderingPostFlushTasksSelector);
  }
}

+ (BOOL)accessInstanceVariablesDirectly { return NO; }

- (id)init
{
  self = [super init];
  if (!self)
    return nil;

  sengine = [[RXScriptEngine alloc] initWithController:self];

  // get the cache line size
  size_t cache_line_size = [RXHardwareProfiler cacheLineSize];

  // allocate enough cache lines to store 2 render states without overlap (to avoid false sharing)
  uint32_t render_state_cache_line_count = cache_line_size / sizeof(struct rx_card_state_render_state);
  if (render_state_cache_line_count == 0)
    // our render state structure is larger than a cache line
    render_state_cache_line_count =
        (sizeof(struct rx_card_state_render_state) / cache_line_size) + ((sizeof(struct rx_card_state_render_state) % cache_line_size) ? 1 : 0);

  // allocate the cache lines
  size_t states_buffer_size = (render_state_cache_line_count * 2 + 1) * cache_line_size;
  release_assert(states_buffer_size > sizeof(struct rx_card_state_render_state) * 2);
  _render_states_buffer = malloc(states_buffer_size);

  // point each render state pointer at the beginning of a cache line
  _front_render_state = (struct rx_card_state_render_state*)BUFFER_OFFSET((uintptr_t)_render_states_buffer & ~(cache_line_size - 1), cache_line_size);
  _back_render_state = BUFFER_OFFSET(_front_render_state, render_state_cache_line_count * cache_line_size);

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

  kerr = semaphore_create(mach_task_self(), &_transitionSemaphore, SYNC_POLICY_FIFO, 0);
  if (kerr != 0)
    goto init_failure;

  _render_lock = OS_SPINLOCK_INIT;
  _state_swap_lock = OS_SPINLOCK_INIT;
  _inventory_update_lock = OS_SPINLOCK_INIT;

  // initialize all the rendering stuff (shaders, textures, buffers, VAOs)
  [self _initializeRendering];
  if (!_initialized) {
    [self release];
    return nil;
  }

  // initialize the mouse state
  _mouse_vector.origin = [(NSView*)g_worldView convertPoint:[[(NSView*)g_worldView window] mouseLocationOutsideOfEventStream] fromView:nil];
  _mouse_vector.size.width = INFINITY;
  _mouse_vector.size.height = INFINITY;
  _mouse_timestamp = RXTimingTimestampDelta(RXTimingNow(), 0);

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

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [_inventory_alpha_interpolators[0] release];
  [_inventory_alpha_interpolators[1] release];
  [_inventory_alpha_interpolators[2] release];
  [_inventory_position_interpolators[0] release];
  [_inventory_position_interpolators[1] release];
  [_inventory_position_interpolators[2] release];

  if (_credits_texture_buffer)
    free(_credits_texture_buffer);

  if (_transitionSemaphore)
    semaphore_destroy(mach_task_self(), _transitionSemaphore);

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

  if (_water_draw_buffer)
    free(_water_draw_buffer);

  [sengine release];

  [super dealloc];
}

- (RXScriptEngine*)scriptEngine { return sengine; }

#pragma mark -
#pragma mark rendering initialization

- (void)_reportShaderProgramError:(NSError*)error
{
  if ([[error domain] isEqualToString:GLShaderCompileErrorDomain]) {
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"%@ shader failed to compile:\n%@\n%@", [[error userInfo] objectForKey:@"GLShaderType"],
            [[error userInfo] objectForKey:@"GLCompileLog"], [[error userInfo] objectForKey:@"GLShaderSource"]);
  } else if ([[error domain] isEqualToString:GLShaderLinkErrorDomain]) {
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"program failed to link:\n%@", [[error userInfo] objectForKey:@"GLLinkLog"]);
  } else {
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"failed to create shader program: %@", error);
  }
}

- (struct rx_transition_program)_loadTransitionShaderWithName:(NSString*)name direction:(RXTransitionDirection)direction context:(CGLContextObj)cgl_ctx
{
  NSError* error;

  struct rx_transition_program program;
  GLint sourceTextureUniform;
  GLint destinationTextureUniform;

  NSString* directionSource = [NSString stringWithFormat:@"#define RX_DIRECTION %d\n", direction];
  NSArray* extraSource = [NSArray arrayWithObjects:@"#version 110\n", directionSource, nil];

  program.program = [[GLShaderProgramManager sharedManager] standardProgramWithFragmentShaderName:name
                                                                                     extraSources:extraSource
                                                                                    epilogueIndex:[extraSource count]
                                                                                          context:cgl_ctx
                                                                                            error:&error];
  if (program.program == 0) {
    [self _reportShaderProgramError:error];
    return program;
  }

  sourceTextureUniform = glGetUniformLocation(program.program, "source");
  glReportError();
  destinationTextureUniform = glGetUniformLocation(program.program, "destination");
  glReportError();

  program.margin_uniform = glGetUniformLocation(program.program, "margin");
  glReportError();
  program.t_uniform = glGetUniformLocation(program.program, "t");
  glReportError();
  program.card_size_uniform = glGetUniformLocation(program.program, "cardSize");
  glReportError();

  glUseProgram(program.program);
  glReportError();
  glUniform1i(sourceTextureUniform, 1);
  glReportError();
  glUniform1i(destinationTextureUniform, 0);
  glReportError();

  if (program.card_size_uniform != -1)
    glUniform2f(program.card_size_uniform, kRXCardViewportSize.width, kRXCardViewportSize.height);

  if (program.margin_uniform != -1)
    glUniform2f(program.margin_uniform, 0.0f, 0.0f);

  glReportError();
  return program;
}

- (void)_initializeRendering
{
  // WARNING: WILL BE RUNNING ON THE MAIN THREAD
  NSError* error;

  // use the load context to prepare our GL objects
  CGLContextObj cgl_ctx = [g_worldView loadContext];
  CGLLockContext(cgl_ctx);
  NSObject<RXOpenGLStateProtocol>* gl_state = RXGetContextState(cgl_ctx);

  // kick start the audio task thread
  [NSThread detachNewThreadSelector:@selector(_audioTaskThread:) toTarget:self withObject:nil];

  // disable client storage for the duration of this method, because we'll either be transferring textures
  // using a PBO or allocating RT textures (which are just surfaces)
  GLenum client_storage = [gl_state setUnpackClientStorage:GL_FALSE];

  // water sfxe

  // create the water draw and readback buffers
  _water_draw_buffer = malloc((kRXCardViewportSize.width * kRXCardViewportSize.height) << 3);
  _water_readback_buffer = BUFFER_OFFSET(_water_draw_buffer, (kRXCardViewportSize.width * kRXCardViewportSize.height) << 2);

  // inventory textures and interpolators

  // get a reference to the extra bitmaps archive, and get the inventory texture descriptors
  MHKArchive* extras_archive = [[RXArchiveManager sharedArchiveManager] extrasArchive:&error];
  if (!extras_archive) {
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"failed to get the Extras archive: %@", [error localizedDescription]);
    return;
  }
  NSDictionary* journal_descriptors = [[g_world extraBitmapsDescriptor] objectForKey:@"Journals"];

  // get the texture descriptors for the inventory textures and compute the total byte size of those textures (packed BGRA format)
  // also compute the maximum inventory width
  NSDictionary* inventoryTextureDescriptors[3];
  uint32_t inventoryTotalTextureSize = 0;
  _inventory_max_width = 0.0f;
  for (GLuint inventory_i = 0; inventory_i < RX_MAX_INVENTORY_ITEMS; inventory_i++) {
    uint16_t bitmapID = [[journal_descriptors objectForKey:RX_INVENTORY_KEYS[inventory_i]] unsignedShortValue];
    inventoryTextureDescriptors[inventory_i] = [extras_archive bitmapDescriptorWithID:bitmapID error:&error];
    if (!inventoryTextureDescriptors[inventory_i]) {
      RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"failed to get inventory texture descriptor for item \"%@\": %@", RX_INVENTORY_KEYS[inventory_i],
              error);
      continue;
    }

    _inventory_sizes[inventory_i] = RXSizeMake([[inventoryTextureDescriptors[inventory_i] objectForKey:@"Width"] unsignedIntValue],
                                               [[inventoryTextureDescriptors[inventory_i] objectForKey:@"Height"] unsignedIntValue]);

    _inventory_max_width += _inventory_sizes[inventory_i].width;
    inventoryTotalTextureSize += (_inventory_sizes[inventory_i].width * _inventory_sizes[inventory_i].height) << 2;
  }

  // load the journal inventory textures in an unpack buffer object
  GLuint inventory_unpack_buffer;
  glGenBuffers(1, &inventory_unpack_buffer);
  glReportError();
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, inventory_unpack_buffer);
  glReportError();

  // allocate the texture buffer (aligned to 128 bytes)
  inventoryTotalTextureSize = (inventoryTotalTextureSize & ~0x7f) + 0x80;
  glBufferData(GL_PIXEL_UNPACK_BUFFER, inventoryTotalTextureSize, NULL, GL_STATIC_DRAW);
  glReportError();

  // map the buffer in
  void* inventoryBuffer = glMapBuffer(GL_PIXEL_UNPACK_BUFFER, GL_WRITE_ONLY);
  glReportError();

  // decompress the textures into the buffer
  for (GLuint inventory_i = 0; inventory_i < RX_MAX_INVENTORY_ITEMS; inventory_i++) {
    uint16_t bitmapID = [[journal_descriptors objectForKey:RX_INVENTORY_KEYS[inventory_i]] unsignedShortValue];
    if (![extras_archive loadBitmapWithID:bitmapID buffer:inventoryBuffer format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED error:&error]) {
      RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"failed to load inventory texture for item \"%@\": %@", RX_INVENTORY_KEYS[inventory_i], error);
      continue;
    }

    inventoryBuffer = BUFFER_OFFSET(inventoryBuffer, (uint32_t)(_inventory_sizes[inventory_i].width * _inventory_sizes[inventory_i].height) << 2);
  }

  // unmap the pixel unpack buffer to begin the DMA transfer
  glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER);
  glReportError();
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
  glReportError();

  // while we DMA the inventory textures, let's do some more work

  // card compositing

  // we need one FBO to render a card's composite texture and one FBO to apply the water effect;
  // as well as matching textures for the color0 attachement point and one extra texture to store the previous frame
  glGenFramebuffersEXT(1, _fbos);
  glGenTextures(1, _textures);

  for (GLuint i = 0; i < 1; i++) {
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _fbos[i]);
    glReportError();

    // bind the texture
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _textures[i]);
    glReportError();

    // texture parameters
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glReportError();

    // allocate memory for the texture
    glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, kRXCardViewportSize.width, kRXCardViewportSize.height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
    glReportError();

    // color0 texture attach
    glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_ARB, _textures[i], 0);
    glReportError();

    // completeness check
    GLenum fboStatus = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
    if (fboStatus != GL_FRAMEBUFFER_COMPLETE_EXT)
      RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"FBO not complete, status 0x%04x\n", (unsigned int)fboStatus);
  }

  // create the card compositing VAO and bind it
  glGenVertexArraysAPPLE(1, &_card_composite_vao);
  glReportError();
  [gl_state bindVertexArrayObject:_card_composite_vao];

  // 4 triangle strip primitives, 4 vertices per strip, [<position.x position.y> <texcoord0.s texcoord0.t>], floats
  _card_composite_va = calloc(64, sizeof(GLfloat));

  // write the vertex attributes
  GLfloat* positions = (GLfloat*)_card_composite_va;
  GLfloat* tex_coords0 = positions + 2;

  // main card composite
  {
    positions[0] = 0.0f;
    positions[1] = kRXCardViewportSize.height;
    tex_coords0[0] = 0.0f;
    tex_coords0[1] = 0.0f;
    positions += 4;
    tex_coords0 += 4;

    positions[0] = kRXCardViewportSize.width;
    positions[1] = kRXCardViewportSize.height;
    tex_coords0[0] = kRXCardViewportSize.width;
    tex_coords0[1] = 0.0f;
    positions += 4;
    tex_coords0 += 4;

    positions[0] = 0.0f;
    positions[1] = 0.0f;
    tex_coords0[0] = 0.0f;
    tex_coords0[1] = kRXCardViewportSize.height;
    positions += 4;
    tex_coords0 += 4;

    positions[0] = kRXCardViewportSize.width;
    positions[1] = 0.0f;
    tex_coords0[0] = kRXCardViewportSize.width;
    tex_coords0[1] = kRXCardViewportSize.height;
  }

  // configure the VAs
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glReportError();

  glEnableVertexAttribArray(RX_ATTRIB_POSITION);
  glVertexAttribPointer(RX_ATTRIB_POSITION, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), _card_composite_va);
  glReportError();

  glEnableVertexAttribArray(RX_ATTRIB_TEXCOORD0);
  glVertexAttribPointer(RX_ATTRIB_TEXCOORD0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), BUFFER_OFFSET(_card_composite_va, 2 * sizeof(GLfloat)));
  glReportError();

  // transitions

  // create the transition source texture
  _transition_source_texture = [RXTexture newStandardTextureWithTarget:GL_TEXTURE_RECTANGLE_ARB size:kRXCardViewportSize context:cgl_ctx lock:NO];

  // shaders

  // card shader
  _card_program =
      [[GLShaderProgramManager sharedManager] standardProgramWithFragmentShaderName:@"card" extraSources:nil epilogueIndex:0 context:cgl_ctx error:&error];
  if (!_card_program)
    [self _reportShaderProgramError:error];

  glUseProgram(_card_program);
  glReportError();

  GLint uniform_loc = glGetUniformLocation(_card_program, "destination_card");
  glReportError();
  glUniform1i(uniform_loc, 0);
  glReportError();

  _modulate_color_uniform = glGetUniformLocation(_card_program, "modulate_color");
  glReportError();
  glUniform4f(_modulate_color_uniform, 1.f, 1.f, 1.f, 1.f);
  glReportError();

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

#if defined(DEBUG)
  // debug rendering

  // create a VAO for all debug rendering
  glGenVertexArraysAPPLE(1, &_debugRenderVAO);
  glReportError();
  [gl_state bindVertexArrayObject:_debugRenderVAO];

  // the fixed-function vertex array is always enabled in the debug VAO
  glEnableClientState(GL_VERTEX_ARRAY);
  glReportError();

  // hotspot debug rendering

  // create a VBO for the hotspot vertices
  glGenBuffers(1, &_hotspotDebugRenderVBO);
  glReportError();
  glBindBuffer(GL_ARRAY_BUFFER, _hotspotDebugRenderVBO);
  glReportError();

  // enable sub-range flushing
  glBufferParameteriAPPLE(GL_ARRAY_BUFFER, GL_BUFFER_FLUSHING_UNMAP_APPLE, GL_FALSE);

  // 4 lines per hotspot, 6 floats per line (coord[x, y] color[r, g, b, a])
  glBufferData(GL_ARRAY_BUFFER, (RX_MAX_RENDER_HOTSPOT + RX_MAX_INVENTORY_ITEMS) * 24 * sizeof(GLfloat), NULL, GL_STREAM_DRAW);
  glReportError();

  // allocate the first element and element count arrays
  _hotspotDebugRenderFirstElementArray = new GLint[RX_MAX_RENDER_HOTSPOT + RX_MAX_INVENTORY_ITEMS];
  _hotspotDebugRenderElementCountArray = new GLint[RX_MAX_RENDER_HOTSPOT + RX_MAX_INVENTORY_ITEMS];
#endif

  // alright, we've done all the work we could, let's now make those inventory textures

  // re-bind the inventory unpack buffer
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, inventory_unpack_buffer);
  glReportError();

  // create the textures and reset inventoryBuffer which we'll use as a buffer offset
  glGenTextures(RX_MAX_INVENTORY_ITEMS, _inventory_textures);
  inventoryBuffer = 0;

  // decompress the textures into the buffer
  for (GLuint inventory_i = 0; inventory_i < RX_MAX_INVENTORY_ITEMS; inventory_i++) {
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _inventory_textures[inventory_i]);
    glReportError();

    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glReportError();

    glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, _inventory_sizes[inventory_i].width, _inventory_sizes[inventory_i].height, 0, GL_BGRA,
                 GL_UNSIGNED_INT_8_8_8_8_REV, inventoryBuffer);
    glReportError();

    inventoryBuffer = BUFFER_OFFSET(inventoryBuffer, (uint32_t)(_inventory_sizes[inventory_i].width * _inventory_sizes[inventory_i].height) << 2);
  }

  // restore state to Riven X assumptions

  // bind program 0 back (Riven X assumption)
  glUseProgram(0);

  // reset the current VAO to 0
  [gl_state bindVertexArrayObject:0];

  // bind 0 to the unpack buffer (e.g. client memory unpacking)
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
  glReportError();

  // restore client storage
  [gl_state setUnpackClientStorage:client_storage];

  // we're done with the inventory unpack buffer
  glDeleteBuffers(1, &inventory_unpack_buffer);

  // new texture, buffer and program objects
  glFlush();

  // done with OpenGL
  CGLUnlockContext(cgl_ctx);

  _initialized = YES;
}

#pragma mark -
#pragma mark audio rendering

- (CFMutableArrayRef)_newSourceArrayFromSoundSets:(NSArray*)sets callbacks:(CFArrayCallBacks*)callbacks
{
  CFMutableArrayRef sources = CFArrayCreateMutable(NULL, 0, callbacks);
  for (NSSet* s in sets) {
    for (RXSound* sound in s) {
      release_assert(sound->source);
      CFArrayAppendValue(sources, sound->source);
    }
  }
  return sources;
}

- (CFMutableArrayRef)_newSourceArrayFromSoundSet:(NSSet*)s callbacks:(CFArrayCallBacks*)callbacks
{ return [self _newSourceArrayFromSoundSets:[NSArray arrayWithObject:s] callbacks:callbacks]; }

- (void)_appendToSourceArray:(CFMutableArrayRef)sources soundSets:(NSArray*)sets
{
  for (NSSet* s in sets) {
    for (RXSound* sound in s) {
      release_assert(sound->source);
      CFArrayAppendValue(sources, sound->source);
    }
  }
}

- (void)_appendToSourceArray:(CFMutableArrayRef)sources soundSet:(NSSet*)s
{ return [self _appendToSourceArray:sources soundSets:[NSArray arrayWithObject:s]]; }

- (void)_updateActiveSources
{
  // WARNING: WILL BE RUNNING ON THE SCRIPT THREAD
  NSMutableSet* soundsToRemove = [NSMutableSet new];
  uint64_t now = RXTimingNow();

  // find expired sounds, removing associated decompressors and sources as we go

  for (RXSound* sound in _activeSounds) {
    if (sound->detach_timestamp && sound->detach_timestamp <= now)
      [soundsToRemove addObject:sound];
  }
  for (RXSound* sound in _activeDataSounds) {
    if (sound->detach_timestamp && sound->detach_timestamp <= now)
      [soundsToRemove addObject:sound];
  }

  // remove expired sounds from the set of active sounds
  [_activeSounds minusSet:soundsToRemove];
  [_activeDataSounds minusSet:soundsToRemove];

  // swap the active sources array
  CFMutableArrayRef newActiveSources = [self _newSourceArrayFromSoundSets:@[ _activeSounds, _activeDataSounds ] callbacks:&g_weakAudioSourceArrayCallbacks];
  CFMutableArrayRef oldActiveSources = _activeSources;

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
  else {
    RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"updated active sources by removing %@", soundsToRemove);
  }
#endif

  // remove the sources for all expired sounds from the sound to source map and prepare the detach and delete array
  if (!_sourcesToDelete)
    _sourcesToDelete = [self _newSourceArrayFromSoundSet:soundsToRemove callbacks:&g_deleteOnReleaseAudioSourceArrayCallbacks];
  else
    [self _appendToSourceArray:_sourcesToDelete soundSet:soundsToRemove];

  // we can now set the source ivar of the sounds to remove to NULL
  for (RXSound* sound in soundsToRemove)
    sound->source = NULL;

  // detach the sources
  RX::AudioRenderer* renderer = (reinterpret_cast<RX::AudioRenderer*>([g_world audioRenderer]));
  renderer->DetachSources(_sourcesToDelete);

  // if automatic graph updates are enabled, we can safely delete the sources,
  // otherwise the responsibility falls on whatever will re-enabled automatic graph updates
  if (renderer->AutomaticGraphUpdates()) {
    CFRelease(_sourcesToDelete);
    _sourcesToDelete = NULL;
  }

  // done with the set
  [soundsToRemove release];
}

- (void)activateSoundGroup:(RXSoundGroup*)soundGroup
{
  // WARNING: MUST RUN ON THE SCRIPT THREAD
  if ([NSThread currentThread] != [g_world scriptThread])
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"activateSoundGroup: MUST RUN ON SCRIPT THREAD" userInfo:nil];

  if (!RXEngineGetBool(@"rendering.ambient"))
    return;

  // cache a pointer to the audio renderer
  RX::AudioRenderer* renderer = (reinterpret_cast<RX::AudioRenderer*>([g_world audioRenderer]));

  // cache the sound group's sound set
  NSSet* soundGroupSounds = [soundGroup sounds];

#if defined(DEBUG)
  RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"activating sound group %@ with sounds: %@", soundGroup, soundGroupSounds);
#endif

  // create an array of new sources
  CFMutableArrayRef sourcesToAdd = CFArrayCreateMutable(NULL, 0, &g_weakAudioSourceArrayCallbacks);

  // copy the active sound set to prepare the new active sound set
  NSMutableSet* newActiveSounds = [_activeSounds mutableCopy];

  // the set of sounds to remove is the set of active sounds minus the incoming sound group's set of sounds
  NSMutableSet* soundsToRemove = [_activeSounds mutableCopy];
  [soundsToRemove minusSet:soundGroupSounds];

  // process new and updated sounds
  for (RXSound* sound in soundGroupSounds) {
    RXSound* active_sound = [_activeSounds member:sound];

    // NEW SOUND
    if (!active_sound) {
      // get a decompressor
      id<MHKAudioDecompression> decompressor = [sound audioDecompressor];
      if (!decompressor) {
        RXOLog2(kRXLoggingAudio, kRXLoggingLevelError, @"failed to get audio decompressor for sound ID %hu", sound->twav_id);
        continue;
      }

      // create an audio source with the decompressor
      sound->source = new RX::CardAudioSource(decompressor, sound->gain * soundGroup->gain, sound->pan, soundGroup->loop);
      release_assert(sound->source);

      // make sure the sound doesn't have a valid detach timestamp
      sound->detach_timestamp = 0;

      // add the sound to the new set of active sounds
      [newActiveSounds addObject:sound];

      // prepare the sourcesToAdd array
      CFArrayAppendValue(sourcesToAdd, sound->source);

#if defined(DEBUG) && DEBUG > 1
      RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"    added new sound %hu to the active mix (source: %p)", sound->twav_id, sound->source);
#endif
    }

    // UPDATE SOUND
    else {
      release_assert(active_sound->source);

      // update the sound's gain and pan (this does not affect the source)
      active_sound->gain = sound->gain;
      active_sound->pan = sound->pan;

      // make sure the sound doesn't have a valid detach timestamp
      active_sound->detach_timestamp = 0;

      // set source looping
      active_sound->source->SetLooping(soundGroup->loop);

      // update the source's gain smoothly
      renderer->RampSourceGain(*(active_sound->source), active_sound->gain * soundGroup->gain, RX_AUDIO_GAIN_RAMP_DURATION);
      active_sound->source->SetNominalGain(active_sound->gain * soundGroup->gain);

      // update the source's stereo panning smoothly
      renderer->RampSourcePan(*(active_sound->source), active_sound->pan, RX_AUDIO_PAN_RAMP_DURATION);
      active_sound->source->SetNominalPan(active_sound->pan);

#if defined(DEBUG) && DEBUG > 1
      RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"    updated sound %hu in the active mix (source: %p)", sound->twav_id, sound->source);
#endif
    }
  }

  // if no fade out is requested, set the detach timestamp of sounds not already scheduled for detach to now
  if (!soundGroup->fadeOutRemovedSounds) {
    for (RXSound* sound in soundsToRemove) {
      if (sound->detach_timestamp == 0)
        sound->detach_timestamp = RXTimingNow();
    }
  }

  // swap the set of active sounds (not atomic, but _activeSounds is only used on the stack thread)
  NSMutableSet* old = _activeSounds;
  _activeSounds = newActiveSounds;
  [old release];

  // disable automatic graph updates on the audio renderer (e.g. begin a transaction)
  renderer->SetAutomaticGraphUpdates(false);

  // FIXME: handle situation where there are not enough busses (in which case
  // we would probably have to do a graph update to really release the busses)
  release_assert(renderer->AvailableMixerBusCount() >= (uint32_t)CFArrayGetCount(sourcesToAdd));

  // update active sources immediately
  [self _updateActiveSources];

  // _updateActiveSources will have removed faded out sounds; make sure those are no longer in soundsToRemove
  [soundsToRemove intersectSet:_activeSounds];

  // now that any sources bound to be detached has been, go ahead and attach as many of the new sources as possible
  if (soundGroup->fadeInNewSounds || _forceFadeInOnNextSoundGroup) {
    // disabling the sources will prevent the fade in from starting before we update the graph
    CFRange everything = CFRangeMake(0, CFArrayGetCount(sourcesToAdd));
    CFArrayApplyFunction(sourcesToAdd, everything, RXCardAudioSourceDisableApplier, [g_world audioRenderer]);
    renderer->AttachSources(sourcesToAdd);
    CFArrayApplyFunction(sourcesToAdd, everything, RXCardAudioSourceFadeInApplier, [g_world audioRenderer]);
  } else {
    renderer->AttachSources(sourcesToAdd);
  }

  // re-enable automatic updates; this will automatically do an update if one is needed
  renderer->SetAutomaticGraphUpdates(true);

  // delete any sources that were detached
  if (_sourcesToDelete) {
    CFRelease(_sourcesToDelete);
    _sourcesToDelete = NULL;
  }

  // enable all the new audio sources
  if (soundGroup->fadeInNewSounds || _forceFadeInOnNextSoundGroup) {
    CFRange everything = CFRangeMake(0, CFArrayGetCount(sourcesToAdd));
    CFArrayApplyFunction(sourcesToAdd, everything, RXCardAudioSourceEnableApplier, [g_world audioRenderer]);
  }

  // schedule a fade out ramp for all to-be-removed sources if the fade out flag is on
  if (soundGroup->fadeOutRemovedSounds) {
    CFMutableArrayRef sourcesToRemove = [self _newSourceArrayFromSoundSet:soundsToRemove callbacks:&g_weakAudioSourceArrayCallbacks];
    renderer->RampSourcesGain(sourcesToRemove, 0.0f, RX_AUDIO_GAIN_RAMP_DURATION);
    CFRelease(sourcesToRemove);

    // the detach timestamp for those sources is now + the ramp duration + some comfort offset
    uint64_t detach_timestamp = RXTimingOffsetTimestamp(RXTimingNow(), RX_AUDIO_GAIN_RAMP_DURATION + 0.5);

    for (RXSound* sound in soundsToRemove)
      sound->detach_timestamp = detach_timestamp;
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

- (void)playDataSound:(RXDataSound*)sound
{
  // WARNING: MUST RUN ON THE SCRIPT THREAD
  if ([NSThread currentThread] != [g_world scriptThread])
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"playDataSound: MUST RUN ON SCRIPT THREAD" userInfo:nil];

  // cache a pointer to the audio renderer
  RX::AudioRenderer* renderer = (reinterpret_cast<RX::AudioRenderer*>([g_world audioRenderer]));

  RXSound* active_sound = [_activeDataSounds member:sound];

  // NEW SOUND
  if (!active_sound) {
    // get a decompressor
    id<MHKAudioDecompression> decompressor = [sound audioDecompressor];
    if (!decompressor) {
      RXOLog2(kRXLoggingAudio, kRXLoggingLevelError, @"failed to get audio decompressor for sound ID %hu", sound->twav_id);
      return;
    }

    // create an audio source with the decompressor
    sound->source = new RX::CardAudioSource(decompressor, sound->gain, sound->pan, false);
    release_assert(sound->source);

    // make sure the sound doesn't have a valid detach timestamp
    sound->detach_timestamp = 0;

    // disable automatic graph updates on the audio renderer (e.g. begin a transaction)
    renderer->SetAutomaticGraphUpdates(false);

    // add the sound to the set of active data sounds
    [_activeDataSounds addObject:sound];

    // update active sources immediately
    [self _updateActiveSources];

    // now that any sources bound to be detached has been, go ahead and attach the new source
    renderer->AttachSource(*(sound->source));

    // set the sound's detatch timestamp to the sound's duration plus some comfort offset
    sound->detach_timestamp = RXTimingOffsetTimestamp(RXTimingNow(), sound->source->Duration() + 0.5);

    // re-enable automatic updates. this will automatically do an update if one is needed
    renderer->SetAutomaticGraphUpdates(true);

    // delete any sources that were detached
    if (_sourcesToDelete) {
      CFRelease(_sourcesToDelete);
      _sourcesToDelete = NULL;
    }
  }

  // UPDATE SOUND
  else {
    release_assert(active_sound->source);

    // update the sound's gain and pan (this does not affect the source)
    active_sound->gain = sound->gain;
    active_sound->pan = sound->pan;

    // update the source's gain smoothly
    renderer->SetSourceGain(*(active_sound->source), active_sound->gain);
    active_sound->source->SetNominalGain(active_sound->gain);

    // update the source's stereo panning smoothly
    renderer->SetSourceGain(*(active_sound->source), active_sound->pan);
    active_sound->source->SetNominalPan(active_sound->pan);

    // reset the sound's source
    active_sound->source->Reset();

    // make sure the sound doesn't have a valid detach timestamp
    active_sound->detach_timestamp = 0;

    // update active sources immediately
    [self _updateActiveSources];

    // set the sound's detatch timestamp to the sound's duration plus some comfort offset
    active_sound->detach_timestamp = RXTimingOffsetTimestamp(RXTimingNow(), sound->source->Duration() + 0.5);
  }

#if defined(DEBUG)
  RXOLog2(kRXLoggingAudio, kRXLoggingLevelDebug, @"playing data sound %@", sound);
#endif
}

- (void)_audioTaskThread:(id)object __attribute__((noreturn))
{
  // WARNING: WILL BE RUNNING ON A DEDICATED THREAD
  NSAutoreleasePool* p = [NSAutoreleasePool new];

  RXSetThreadName("audio task");

  CFRange everything = CFRangeMake(0, 0);
  void* renderer = [g_world audioRenderer];

  // let's get a bit more attention
  thread_extended_policy_data_t extendedPolicy;
  extendedPolicy.timeshare = false;
  thread_policy_set(pthread_mach_thread_np(pthread_self()), THREAD_EXTENDED_POLICY, (thread_policy_t) & extendedPolicy, THREAD_EXTENDED_POLICY_COUNT);

  thread_precedence_policy_data_t precedencePolicy;
  precedencePolicy.importance = 63;
  thread_policy_set(pthread_mach_thread_np(pthread_self()), THREAD_PRECEDENCE_POLICY, (thread_policy_t) & precedencePolicy, THREAD_PRECEDENCE_POLICY_COUNT);

  uint32_t cycles = 0;
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
}

#pragma mark -
#pragma mark riven script protocol implementation

- (void)queuePicture:(RXPicture*)picture
{
  uint32_t index = [_back_render_state->pictures indexOfObject:picture];
  if (index != NSNotFound)
    [_back_render_state->pictures removeObjectAtIndex:index];

  [_back_render_state->pictures addObject:picture];

  if (index == NSNotFound)
    [[picture owner] retain];

#if defined(DEBUG)
  RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"queued picture %@", picture);
#endif
}

- (void)enableMovie:(RXMovie*)movie
{
  OSSpinLockLock(&_render_lock);

  uint32_t index;

  if (_movies_to_disable_on_next_update) {
    index = [_movies_to_disable_on_next_update indexOfObject:movie];
    if (index != NSNotFound)
      [_movies_to_disable_on_next_update removeObjectAtIndex:index];
  }

  index = [_active_movies indexOfObject:movie];
  if (index != NSNotFound)
    [_active_movies removeObjectAtIndex:index];

  [_active_movies addObject:movie];

  if (index == NSNotFound)
    [[movie owner] retain];

  OSSpinLockUnlock(&_render_lock);

#if defined(DEBUG)
  RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"enabled movie %@ [%d active movies]", movie, [_active_movies count]);
#endif
}

- (void)disableMovie:(RXMovie*)movie
{
  OSSpinLockLock(&_render_lock);

  uint32_t index = [_active_movies indexOfObject:movie];
  if (index != NSNotFound) {
    [[movie owner] release];
    [_active_movies removeObjectAtIndex:index];
  }

  OSSpinLockUnlock(&_render_lock);

#if defined(DEBUG)
  RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"disabled movie %@ [%d active movies]", movie, [_active_movies count]);
#endif
}

- (void)disableAllMovies
{
  CFArrayApplyFunction((CFArrayRef)_active_movies, CFRangeMake(0, [_active_movies count]), rx_release_owner_applier, self);
  [_active_movies removeAllObjects];

#if defined(DEBUG)
  RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"disabled all movies");
#endif
}

- (void)_disableMoviesToDisableOnNextUpdate
{
  CFArrayApplyFunction((CFArrayRef)_movies_to_disable_on_next_update, CFRangeMake(0, [_movies_to_disable_on_next_update count]), rx_release_owner_applier,
                       self);
  [_active_movies removeObjectsInArray:_movies_to_disable_on_next_update];

  [_movies_to_disable_on_next_update release];
  _movies_to_disable_on_next_update = nil;

#if defined(DEBUG)
  RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"disabled movies to disable on next update [%d active movies]", [_active_movies count]);
#endif
}

- (void)disableAllMoviesOnNextScreenUpdate
{
  [_movies_to_disable_on_next_update release];
  _movies_to_disable_on_next_update = [_active_movies copy];
}

- (BOOL)isMovieEnabled:(RXMovie*)movie { return ([_active_movies indexOfObject:movie] == NSNotFound) ? NO : YES; }

- (void)queueSpecialEffect:(rx_card_sfxe*)sfxe owner:(id)owner
{
  if (_back_render_state->water_fx.sfxe == sfxe)
    return;

  _back_render_state->water_fx.sfxe = sfxe;
  _back_render_state->water_fx.current_frame = 0;
  if (sfxe)
    _back_render_state->water_fx.owner = owner;
  else
    _back_render_state->water_fx.owner = nil;
}

- (void)disableWaterSpecialEffect
{
  OSSpinLockLock(&_render_lock);
  _water_sfx_disabled = YES;
  OSSpinLockUnlock(&_render_lock);
}

- (void)enableWaterSpecialEffect
{
  OSSpinLockLock(&_render_lock);
  _water_sfx_disabled = NO;
  OSSpinLockUnlock(&_render_lock);
}

- (void)queueTransition:(RXTransition*)transition
{
  // queue the transition
  [_transitionQueue addObject:transition];
#if defined(DEBUG)
  RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"queued transition %@ [queue depth=%u]", transition, [_transitionQueue count]);
#endif
}

- (void)enableTransitionDequeueing { _disable_transition_dequeueing = NO; }

- (void)disableTransitionDequeueing { _disable_transition_dequeueing = YES; }

- (void)update
{
  // WARNING: MUST RUN ON THE SCRIPT THREAD
  if ([NSThread currentThread] != [g_world scriptThread])
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"update MUST RUN ON SCRIPT THREAD" userInfo:nil];

  // if we'll queue a transition, hide the cursor; we want to do this before waiting for any ongoing transition so that if there is one,
  // when it completes the cursor won't flash on screen (race condition between this thread and the render thread)
  if ([_transitionQueue count] > 0 && !_disable_transition_dequeueing)
    [self hideMouseCursor];

  // if a transition is ongoing, wait until its done
  mach_timespec_t wait_time = {0, static_cast<clock_res_t>(kRXTransitionDuration * 1e9)};
  while (_front_render_state->transition != nil)
    semaphore_timedwait(_transitionSemaphore, wait_time);

  // dequeue the top transition
  if ([_transitionQueue count] > 0 && !_disable_transition_dequeueing) {
    _back_render_state->transition = [[_transitionQueue objectAtIndex:0] retain];
    [_transitionQueue removeAllObjects];

#if defined(DEBUG)
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"dequeued transition %@ [queue depth=%u]", _back_render_state->transition, [_transitionQueue count]);
#endif
  }

  // retain the water effect owner at this time, since we're about to swap the render states
  [_back_render_state->water_fx.owner retain];

  // indicate that this is a new render state
  _back_render_state->refresh_static = YES;

  // save the front render state
  struct rx_card_state_render_state* previous_front_render_state = _front_render_state;

  // take the render lock
  OSSpinLockLock(&_render_lock);

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

  if (_movies_to_disable_on_next_update)
    [self _disableMoviesToDisableOnNextUpdate];

  // we can resume rendering now
  OSSpinLockUnlock(&_render_lock);

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
  RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"updated render state, front card=%@", _front_render_state->card);
#endif

  // if the front card has changed, we need to reap the back render state's card and put the front card in it
  if (_front_render_state->new_card) {
    // reclaim the back render state's card
    [_back_render_state->card release];
    _back_render_state->card = _front_render_state->card;

    // show the mouse cursor again (matches the hideMousrCursor in setActiveCardWithSimpleDescriptor
    [self showMouseCursor];
  }
}

- (void)beginEndCredits
{
  OSSpinLockLock(&_render_lock);
  _render_credits = YES;
  _credits_state = 0;
  OSSpinLockUnlock(&_render_lock);

  [self hideMouseCursor];
}

#pragma mark -
#pragma mark card switching

- (void)_loadNewGameStateAndShowCursor
{
  // WARNING: MUST RUN ON THE MAIN THREAD
  if (!pthread_main_np())
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_loadNewGameStateAndShowCursor: MUST RUN ON MAIN THREAD" userInfo:nil];

  // FIXME: we need to clear the autosave somehow such that Riven X doesn't load back the card just before the end credits on the next launch
  RXGameState* gs = [[RXGameState alloc] init];
  [g_world loadGameState:gs];
  [gs release];

  // show the mouse cursor again (balances the hideMouseCursor in -beginEndCredits; we do this after
  // calling newDocument: since loading a new game state hides the cursor and thus garantees that the
  // cursor won't flash on the screen until the new game has loaded in
  [self showMouseCursor];
}

- (void)_endCreditsAndBeginNewGame
{
  // WARNING: MUST RUN ON THE MAIN THREAD
  if (!pthread_main_np())
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_endCreditsAndBeginNewGame: MUST RUN ON MAIN THREAD" userInfo:nil];

  // clear the active card
  [self clearActiveCardWaitingUntilDone:YES];

  // disable credits rendering mode now that the active card has been cleared
  OSSpinLockLock(&_render_lock);
  _render_credits = NO;
  OSSpinLockUnlock(&_render_lock);

  // load a new game; note that we cannot use newDocument: since that method is disabled while
  // there is activity on the script thread (as expressed by hotspot handling being disabled,
  // which is going to be the case when this method executes)
  // NOTE: clearActiveCardWaitingUntilDone: will have queued a notification on the main thread
  //       with a nil card (as expected); this notification will however interfere with the normal
  //       game loading sequence if we don't handle it before we execute loadGameState:, and so we
  //       queue up another method that will load a new game state and call showMouseCursor
  [self performSelectorOnMainThread:@selector(_loadNewGameStateAndShowCursor) withObject:nil waitUntilDone:NO];
}

- (void)_postCardSwitchNotification:(RXCard*)newCard
{
  // WARNING: MUST RUN ON THE MAIN THREAD
  [[NSNotificationCenter defaultCenter] postNotificationName:@"RXActiveCardDidChange" object:newCard];
}

- (void)_broadcastCurrentCard:(NSNotification*)notification
{
  OSSpinLockLock(&_state_swap_lock);
  [self _postCardSwitchNotification:_front_render_state->card];
  OSSpinLockUnlock(&_state_swap_lock);
}

- (void)_switchCardWithSimpleDescriptor:(RXSimpleCardDescriptor*)scd
{
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
    if ([[activeStack key] isEqualToString:scd->stackKey] && scd->cardID == [activeID unsignedShortValue]) {
      new_card = [front_card retain];
#if (DEBUG)
      RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"reloading front card: %@", front_card);
#endif
    }
  }

  // if we're switching to a different card, create it
  if (new_card == nil) {
    // if we don't have the stack, bail
    RXStack* stack = [g_world loadStackWithKey:scd->stackKey];
    if (!stack) {
      RXOLog2(kRXLoggingEngine, kRXLoggingLevelError, @"aborting _switchCardWithSimpleDescriptor because stack '%@' could not be loaded", scd->stackKey);
      return;
    }

    // FIXME: need to be smarter about card loading (cache, locality, etc)
    // load the new card in
    RXCardDescriptor* cd = [[RXCardDescriptor alloc] initWithStack:stack ID:scd->cardID];
    if (!cd)
      @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"COULD NOT FIND CARD IN STACK" userInfo:nil];

    new_card = [[RXCard alloc] initWithCardDescriptor:cd];
    [cd release];

#if (DEBUG)
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"switch card: {from=%@, to=%@}", _front_render_state->card, new_card);
#endif

    // run the close card script on the old card
    [sengine closeCard];
  }

  // if the back state's new_card field is YES, we are performing a switch card before we ran a single
  // screen update for the previous card; in such a case, we need to show the mouse cursor, otherwise
  // the counter will become unbalanced (since -update normally performs a show mouse cursor to match
  // the hide mouse cursor in setActiveCardWithSimpleDescriptor)
  if (_back_render_state->new_card)
    [self showMouseCursor];

  // setup the back render state; notice that the ownership of new_card is
  // transferred to the back render state and thus we will not need a release
  // elsewhere to match the card's allocation
  _back_render_state->card = new_card;
  _back_render_state->new_card = YES;
  _back_render_state->transition = nil;

  // we have to update the current card in the game state now, otherwise refresh
  // card commands will jump back to the old card
  [[g_world gameState] setCurrentCard:[[new_card descriptor] simpleDescriptor]];
  [sengine setCard:new_card];

  // notify that the front card has changed
  [self performSelectorOnMainThread:@selector(_postCardSwitchNotification:) withObject:new_card waitUntilDone:NO];

  // run the open card script on the new card
  [sengine openCard];
}

- (void)_clearActiveCard
{
  // WARNING: MUST RUN ON THE SCRIPT THREAD
  if ([NSThread currentThread] != [g_world scriptThread])
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_clearActiveCard: MUST RUN ON SCRIPT THREAD" userInfo:nil];

  // setup the back render state
  _back_render_state->card = nil;
  _back_render_state->new_card = YES;
  _back_render_state->transition = nil;

  // run the close card script on the old card; note that we do not need to
  // protect access to the front card since this method will always execute
  // on the script thread
  [sengine closeCard];

  // wipe out the transition queue
  [_transitionQueue removeAllObjects];

  // wipe out all movies
  [self disableAllMoviesOnNextScreenUpdate];

  // synthesize and activate an empty sound group
  RXSoundGroup* sgroup = [RXSoundGroup new];
  sgroup->gain = 1.0f;
  sgroup->loop = NO;
  sgroup->fadeOutRemovedSounds = YES;
  sgroup->fadeInNewSounds = NO;
  [self activateSoundGroup:sgroup];
  [sgroup release];

  // must hide the mouse cursor since -update will perform a show mouse cursor
  [self hideMouseCursor];

  // fake a swap render state
  [self update];

  // notify that the front card has changed
  [self performSelectorOnMainThread:@selector(_postCardSwitchNotification:) withObject:nil waitUntilDone:NO];
}

- (void)setActiveCardWithSimpleDescriptor:(RXSimpleCardDescriptor*)scd waitUntilDone:(BOOL)wait
{
  // NOTE: CAN RUN ON ANY THREAD
  if (!scd)
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"STACK DESCRIPTOR CANNOT BE NIL" userInfo:nil];

  // hide the mouse cursor and switch card on the script thread
  [self hideMouseCursor];
  [self performSelector:@selector(_switchCardWithSimpleDescriptor:) withObject:scd inThread:[g_world scriptThread] waitUntilDone:wait];
}

- (void)setActiveCardWithStack:(NSString*)stackKey ID:(uint16_t)cardID waitUntilDone:(BOOL)wait
{
  // NOTE: CAN RUN ON ANY THREAD
  if (!stackKey)
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"STACK KEY CANNOT BE NIL" userInfo:nil];

  RXSimpleCardDescriptor* des = [[RXSimpleCardDescriptor alloc] initWithStackKey:stackKey ID:cardID];
  [self setActiveCardWithSimpleDescriptor:des waitUntilDone:wait];
  [des release];
}

- (void)clearActiveCardWaitingUntilDone:(BOOL)wait
{ [self performSelector:@selector(_clearActiveCard) withObject:nil inThread:[g_world scriptThread] waitUntilDone:wait]; }

#pragma mark -
#pragma mark graphics rendering

- (void)_renderCardWithTimestamp:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx
{
  // WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD

  // read the front render state pointer once and alias it for this method
  struct rx_card_state_render_state* r = _front_render_state;

  // draw in the dynamic RT
  glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _fbos[RX_CARD_DYNAMIC_RENDER_INDEX]);
  glReportError();

  // use the rect texture program
  glUseProgram(_card_program);
  glReportError();

  // flip the y axis
  glMatrixMode(GL_MODELVIEW);
  glTranslatef(0.f, kRXCardViewportSize.height, 0.f);
  glScalef(1.0f, -1.0f, 1.0f);

  // render static card pictures only when necessary
  if (r->refresh_static) {
    // render each picture
    for (id<RXRenderingProtocol> renderObject in r->pictures)
      [renderObject render:outputTime inContext:cgl_ctx framebuffer:_fbos[RX_CARD_DYNAMIC_RENDER_INDEX]];
  }

  if (r->water_fx.sfxe && !_water_sfx_disabled) {
    // if we refreshed pictures, we need to reset the special effect and copy the RT back to main memory
    if (r->refresh_static) {
      r->water_fx.current_frame = 0;
      r->water_fx.frame_timestamp = 0;

      // we need to immediately readback the dynamic RT into the water readback buffer and copy the content into the water draw buffer
      glFlush();
      glReadPixels(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _water_readback_buffer);
      glReportError();

      memcpy(_water_draw_buffer, _water_readback_buffer, kRXCardViewportSize.width * kRXCardViewportSize.height << 2);
    }

    // if the special effect frame timestamp is 0 or expired, update the special effect texture
    double fps_inverse = 1.0 / r->water_fx.sfxe->record->fps;
    if (r->water_fx.frame_timestamp == 0 || RXTimingTimestampDelta(outputTime->hostTime, r->water_fx.frame_timestamp) >= fps_inverse) {
      // run the water microprogram for the current sfxe frame
      union {
        uint16_t* p_int16;
        void* p_void;
      } mp;
      mp.p_void = BUFFER_OFFSET(r->water_fx.sfxe->record, r->water_fx.sfxe->offsets[r->water_fx.current_frame]);

      uint16_t draw_row = r->water_fx.sfxe->record->rect.top;
      while (*mp.p_int16 != 4) {
        if (*mp.p_int16 == 1) {
          draw_row++;
        } else if (*mp.p_int16 == 3) {
          memcpy(BUFFER_OFFSET(_water_draw_buffer, (draw_row * kRXCardViewportSize.width + mp.p_int16[1]) << 2),
                 BUFFER_OFFSET(_water_readback_buffer, (mp.p_int16[3] * kRXCardViewportSize.width + mp.p_int16[2]) << 2), mp.p_int16[4] << 2);
          mp.p_int16 += 4;
        } else {
          abort();
        }

        mp.p_int16++;
      }

      // update the dynamic RT texture from the water draw buffer
      glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _textures[RX_CARD_DYNAMIC_RENDER_INDEX]);
      glReportError();
      glTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, 0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV,
                      _water_draw_buffer);
      glReportError();

      // increment the special effect frame counter
      r->water_fx.current_frame = (r->water_fx.current_frame + 1) % r->water_fx.sfxe->record->frame_count;
      r->water_fx.frame_timestamp = outputTime->hostTime;
    }
  }

  // render movies at the very end
  for (id<RXRenderingProtocol> renderObject in _active_movies)
    _movieRenderDispatch.imp(renderObject, _movieRenderDispatch.sel, outputTime, cgl_ctx, _fbos[RX_CARD_DYNAMIC_RENDER_INDEX]);

  // un-flip the y axis
  glLoadIdentity();

  // static content has been refreshed at the end of this method
  r->refresh_static = NO;
}

- (void)_postFlushCard:(const CVTimeStamp*)outputTime
{
  for (RXMovie* movie in _active_movies)
    _movieFlushTasksDispatch.imp(movie, _movieFlushTasksDispatch.sel, outputTime);
}

- (void)_renderInventory:(CGLContextObj)cgl_ctx
{
  RXGameState* gs = [g_world gameState];
  NSObject<RXOpenGLStateProtocol>* gl_state = RXGetContextState(cgl_ctx);

  // build a new set of inventory item flags; note that for the trap book,
  // the variable has to be exactly set to 1; in particular, atrapbook can be
  // 3 when Gehn takes it from the player but the player refuses to use it
  uint32_t new_flags = 0;
  if ([gs unsigned32ForKey:@"aatrusbook"])
    new_flags |= 1 << RX_INVENTORY_ATRUS;
  if ([gs unsigned32ForKey:@"acathbook"])
    new_flags |= 1 << RX_INVENTORY_CATHERINE;
  if ([gs unsigned32ForKey:@"atrapbook"] == 1)
    new_flags |= 1 << RX_INVENTORY_TRAP;

  OSSpinLockLock(&_inventory_update_lock);

  // update the inventory flags
  uint32_t old_flags = _inventory_flags;
  _inventory_flags = new_flags;

  // compute inventory item origin y, sizes and total width
  float total_inventory_width = 0.0f;
  for (GLuint inventory_i = 0; inventory_i < RX_MAX_INVENTORY_ITEMS; inventory_i++) {
    // only process enabled items
    if (!(new_flags & (1 << inventory_i)))
      continue;

    CGFloat ar = CGFloat(_inventory_sizes[inventory_i].width) / CGFloat(_inventory_sizes[inventory_i].height);
    _inventory_frames[inventory_i].size.height = kRXInventorySize.height - kRXInventoryVerticalMargin;
    _inventory_frames[inventory_i].size.width = ar * _inventory_frames[inventory_i].size.height;

    // compute the y position of the items
    _inventory_frames[inventory_i].origin.y = (kRXInventorySize.height - _inventory_frames[inventory_i].size.height) * 0.5;

    total_inventory_width += _inventory_frames[inventory_i].size.width + RX_INVENTORY_MARGIN;
  }

  // compute the initial inventory x offset
  float x_offset = (_inventory_max_width / 2.0f) - (total_inventory_width / 2.0f);

  // compute the x position of every active inventory item
  for (GLuint inventory_i = 0; inventory_i < RX_MAX_INVENTORY_ITEMS; inventory_i++) {
    if (!(new_flags & (1 << inventory_i)))
      continue;

    _inventory_frames[inventory_i].origin.x = x_offset;
    x_offset = _inventory_frames[inventory_i].origin.x + _inventory_frames[inventory_i].size.width + RX_INVENTORY_MARGIN;
  }

  // compute the new inventory base x offset now, since we need it to compute the hotspot frames
  rx_size_t viewport = RXGetGLViewportSize();
  float new_inventory_base_x_offset = (viewport.width / 2.0f) - (_inventory_max_width / 2.0f);

  // compute the y position and hotspot frame of every active inventory item
  for (GLuint inventory_i = 0; inventory_i < RX_MAX_INVENTORY_ITEMS; inventory_i++) {
    if (!(new_flags & (1 << inventory_i)))
      continue;

    // compute the hotspot frame
    _inventory_hotspot_frames[inventory_i].origin.x = _inventory_frames[inventory_i].origin.x + new_inventory_base_x_offset;
    _inventory_hotspot_frames[inventory_i].origin.y = _inventory_frames[inventory_i].origin.y;
    _inventory_hotspot_frames[inventory_i].size.width = _inventory_frames[inventory_i].size.width;
    _inventory_hotspot_frames[inventory_i].size.height = _inventory_frames[inventory_i].size.height;
  }

  // we can unlock the inventory update lock now since the rest of the work only affects the rendering thread
  OSSpinLockUnlock(&_inventory_update_lock);

  // get the active state of the entire inventory HUD
  BOOL inv_active = [gs unsigned32ForKey:@"ainventory"];
  BOOL active_interpolators = (_inventory_alpha_interpolators[0] || _inventory_alpha_interpolators[1] || _inventory_alpha_interpolators[2]) ? YES : NO;
  BOOL visible_items = (_inventory_alpha[0] > 0.0f || _inventory_alpha[1] > 0.0f || _inventory_alpha[2] > 0.0f) ? YES : NO;
  BOOL render_inv = (inv_active || active_interpolators || visible_items) ? YES : NO;

  // configure global rendering state for the inventory if we're going to be drawing it
  if (render_inv) {
    // configure blending to use a constant alpha as the blend factor
    glBlendFuncSeparate(GL_CONSTANT_ALPHA, GL_ONE_MINUS_CONSTANT_ALPHA, GL_CONSTANT_ALPHA, GL_ONE_MINUS_CONSTANT_ALPHA);
    glBlendEquationSeparate(GL_FUNC_ADD, GL_FUNC_ADD);
    glEnable(GL_BLEND);
    glReportError();

    // use the standard card program
    glUseProgram(_card_program);
    glReportError();

    // bind the card composite VAO
    [gl_state bindVertexArrayObject:_card_composite_vao];
  }

  // get pointers into the card composite array
  GLfloat* buffer = (GLfloat*)_card_composite_va;
  GLfloat* positions = buffer + 16;
  GLfloat* tex_coords0 = positions + 2;

  // update position animations; new animations have UINT64_MAX as their start time
  for (uint32_t inv_i = 0; inv_i < RX_MAX_INVENTORY_ITEMS; inv_i++) {
    double duration;
    RXAnimation* animation;

    // inventory bit
    uint32_t inv_bit = 1U << inv_i;

    // alias the current interpolators now
    RXLinearInterpolator* pos_interpolator = (RXLinearInterpolator*)_inventory_position_interpolators[inv_i];
    RXLinearInterpolator* alpha_interpolator = (RXLinearInterpolator*)_inventory_alpha_interpolators[inv_i];

    // get the current x position of the item and subtract from it the base inventory x offset
    float pos_x = positions[inv_i * 16] - _inventory_base_x_offset;

    // if the position has changed, setup a position interpolator
    float final_position = _inventory_frames[inv_i].origin.x;
    if ((pos_interpolator && fnotequal(pos_interpolator->end, final_position)) || (!pos_interpolator && fnotequal(pos_x, final_position))) {
      duration = (pos_interpolator) ? [[pos_interpolator animation] progress] : 1.0;
      [pos_interpolator release];

      // if the item has just been activated and has no interpolators, don't configure a position interpolator, which means
      // that the item will start fading in at its final position
      if ((new_flags & inv_bit) && !(old_flags & inv_bit) && !pos_interpolator && !alpha_interpolator) {
        pos_interpolator = nil;
      } else {
        animation = [[RXCannedAnimation alloc] initWithDuration:duration curve:RXAnimationCurveSquareSine];
        [animation startAt:UINT64_MAX];
        pos_interpolator = [[RXLinearInterpolator alloc] initWithAnimation:animation start:pos_x end:final_position];
        [animation release];
      }

      _inventory_position_interpolators[inv_i] = pos_interpolator;
    }
  }

  // determine the desired global alpha value based on the inventory focus state
  float global_alpha = (_inventory_has_focus) ? 1.0f : RX_INVENTORY_UNFOCUSED_ALPHA;

  // update alpha animations; new animations have UINT64_MAX as their start time
  for (uint32_t inv_i = 0; inv_i < RX_MAX_INVENTORY_ITEMS; inv_i++) {
    float start;
    double duration;
    RXAnimation* animation;

    // inventory bit
    uint32_t inv_bit = 1U << inv_i;

    RXLinearInterpolator* alpha_interpolator = (RXLinearInterpolator*)_inventory_alpha_interpolators[inv_i];

    // figure out the alpha of the item based on the inventory state flags and the global alpha
    float item_alpha;
    if (!inv_active) {
      item_alpha = 0.0f;
    } else if ((new_flags & inv_bit) && !(old_flags & inv_bit)) {
      // item was activated, its destination alpha should be 1
      item_alpha = 1.0f;
      _inventory_alpha_interpolator_uninterruptible_flags |= inv_bit;
    } else if (!(new_flags & inv_bit) && (old_flags & inv_bit)) {
      // item was deactivated, its destination alpha should be 0
      item_alpha = 0.0f;
      _inventory_alpha_interpolator_uninterruptible_flags |= inv_bit;
    } else if ((new_flags & inv_bit) && !(_inventory_alpha_interpolator_uninterruptible_flags & inv_bit)) {
      // item is active and does not have an active uninterruptible alpha interpolator;
      // alpha should be the global alpha
      item_alpha = global_alpha;
    } else {
      // no change in target alpha
      item_alpha = _inventory_alpha[inv_i];
    }

    // schedule an alpha animation if the new item alpha and the current item alpha differ
    if (fnotequal(item_alpha, _inventory_alpha[inv_i])) {
      // the start value of the alpha animation is either the current alpha value or the current value
      // of the alpha interpolator if there is one
      start = (alpha_interpolator) ? [alpha_interpolator value] : _inventory_alpha[inv_i];

      // the duration of the animation is the duration of a full fade
      // (from 0.0 to 1.0), which is 1.0 times the distance (which means
      // that if the distance is shorter, the duration will be shorter;
      // in order words we're aiming at a constant fade speed)
      duration = 1.0 * fabs(item_alpha - start);

      [alpha_interpolator release];

      if ((new_flags & inv_bit) && !(old_flags & inv_bit)) {
        // the fade-in animation a little bit more complex...
        alpha_interpolator = (RXLinearInterpolator*)[RXChainingInterpolator new];
        RXLinearInterpolator* interpolator;

        // first add a 0->0 interpolator for 0.5 seconds, but only if
        // the item is not visible and there is another active item
        if (start == 0.0f && (new_flags & ~inv_bit)) {
          animation = [[RXCannedAnimation alloc] initWithDuration:0.5 curve:RXAnimationCurveSquareSine];
          [animation startAt:UINT64_MAX];
          interpolator = [[RXLinearInterpolator alloc] initWithAnimation:animation start:0.0f end:0.0f];
          [animation release];

          [(RXChainingInterpolator*)alpha_interpolator addInterpolator:interpolator];
          [interpolator release];
        }

        // then add in the normal fade-in interpolator
        animation = [[RXCannedAnimation alloc] initWithDuration:duration curve:RXAnimationCurveSquareSine];
        [animation startAt:UINT64_MAX];
        interpolator = [[RXLinearInterpolator alloc] initWithAnimation:animation start:start end:item_alpha];
        [animation release];

        [(RXChainingInterpolator*)alpha_interpolator addInterpolator:interpolator];
        [interpolator release];

        // then add the alpha strobing interpolator
        animation = [[RXSineCurveAnimation alloc] initWithDuration:4.0 frequency:2.0f];
        [animation startAt:UINT64_MAX];
        interpolator = [[RXLinearInterpolator alloc] initWithAnimation:animation start:1.0f end:0.6f];
        [animation release];

        [(RXChainingInterpolator*)alpha_interpolator addInterpolator:interpolator];
        [interpolator release];

        // then finally had a slower animation to the final value
        animation = [[RXCannedAnimation alloc] initWithDuration:1.0 curve:RXAnimationCurveSquareSine];
        [animation startAt:UINT64_MAX];
        interpolator = [[RXLinearInterpolator alloc] initWithAnimation:animation start:1.0f end:RX_INVENTORY_UNFOCUSED_ALPHA];
        [animation release];

        [(RXChainingInterpolator*)alpha_interpolator addInterpolator:interpolator];
        [interpolator release];

        // set the item alpha to the actual end alpha
        item_alpha = RX_INVENTORY_UNFOCUSED_ALPHA;
      } else {
        animation = [[RXCannedAnimation alloc] initWithDuration:duration curve:RXAnimationCurveSquareSine];
        [animation startAt:UINT64_MAX];
        alpha_interpolator = [[RXLinearInterpolator alloc] initWithAnimation:animation start:start end:item_alpha];
        [animation release];
      }

      // update the item's "desired" alpha and current alpha interpolator
      _inventory_alpha_interpolators[inv_i] = alpha_interpolator;
      _inventory_alpha[inv_i] = item_alpha;
    }
  }

  // the true start time for new animations is now
  uint64_t anim_start_time = RXTimingNow();

  // update the inventory base x offset with the new offset
  _inventory_base_x_offset = new_inventory_base_x_offset;

  // render the items
  for (uint32_t inv_i = 0; inv_i < RX_MAX_INVENTORY_ITEMS; inv_i++) {
    // inventory bit
    uint32_t inv_bit = 1U << inv_i;

    // alias the current interpolators now
    RXLinearInterpolator* pos_interpolator = (RXLinearInterpolator*)_inventory_position_interpolators[inv_i];
    RXLinearInterpolator* alpha_interpolator = (RXLinearInterpolator*)_inventory_alpha_interpolators[inv_i];

    // set the start time of animations that have UINT64_MAX as their start time
    if (pos_interpolator && [[pos_interpolator animation] startTimestamp] == UINT64_MAX)
      [[pos_interpolator animation] startAt:anim_start_time];
    if (alpha_interpolator && [[alpha_interpolator animation] startTimestamp] == UINT64_MAX)
      [[alpha_interpolator animation] startAt:anim_start_time];

    // get the base X position of the item
    float base_x = _inventory_base_x_offset + ((pos_interpolator) ? [pos_interpolator value] : _inventory_frames[inv_i].origin.x);

    // update the current position of the item based on the base X position
    positions[0] = base_x;
    positions[1] = _inventory_frames[inv_i].origin.y;
    positions += 4;

    positions[0] = base_x + _inventory_frames[inv_i].size.width;
    positions[1] = _inventory_frames[inv_i].origin.y;
    positions += 4;

    positions[0] = base_x;
    positions[1] = _inventory_frames[inv_i].origin.y + _inventory_frames[inv_i].size.height;
    positions += 4;

    positions[0] = base_x + _inventory_frames[inv_i].size.width;
    positions[1] = _inventory_frames[inv_i].origin.y + _inventory_frames[inv_i].size.height;
    positions += 4;

    // tex coords are always the same
    tex_coords0[0] = 0.0f;
    tex_coords0[1] = _inventory_sizes[inv_i].height;
    tex_coords0 += 4;

    tex_coords0[0] = _inventory_sizes[inv_i].width;
    tex_coords0[1] = _inventory_sizes[inv_i].height;
    tex_coords0 += 4;

    tex_coords0[0] = 0.0f;
    tex_coords0[1] = 0.0f;
    tex_coords0 += 4;

    tex_coords0[0] = _inventory_sizes[inv_i].width;
    tex_coords0[1] = 0.0f;
    tex_coords0 += 4;

    // if the item is enabled or has active interpolators, draw it
    // (but only if the inventory as a whole is active)
    if (render_inv && (pos_interpolator || alpha_interpolator || (new_flags & inv_bit))) {
      float alpha = (alpha_interpolator) ? [alpha_interpolator value] : _inventory_alpha[inv_i];
      glBlendColor(1.f, 1.f, 1.f, alpha);
      glReportError();

      glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _inventory_textures[inv_i]);
      glReportError();
      glDrawArrays(GL_TRIANGLE_STRIP, 4 + 4 * inv_i, 4);
      glReportError();
    }

    // if the position interpolator is done, release it
    if (pos_interpolator && [pos_interpolator isDone]) {
      [pos_interpolator release];
      _inventory_position_interpolators[inv_i] = nil;
    }

    // if the alpha interpolator is done, release it
    if (alpha_interpolator && [alpha_interpolator isDone]) {
      [alpha_interpolator release];
      _inventory_alpha_interpolators[inv_i] = nil;
      _inventory_alpha_interpolator_uninterruptible_flags &= ~inv_bit;
    }
  }

  // restore graphics state
  if (render_inv) {
    glDisable(GL_BLEND);
    glUseProgram(0);
    [gl_state bindVertexArrayObject:0];
    glReportError();
  }
}

- (void)_renderCredits:(CGLContextObj)cgl_ctx
{
  NSObject<RXOpenGLStateProtocol>* gl_state = RXGetContextState(cgl_ctx);
  uint64_t now = RXTimingNow();

  if (_credits_state == 0) {
    // initialize the credits

    // start time is now
    _credits_start_time = now;

    // allocate the credit texture buffer
    _credits_texture_buffer = malloc(360 * 784 * 4);

    // create the credits texture and load the first credits picture in it
    MHKArchive* archive = [[RXArchiveManager sharedArchiveManager] extrasArchive:NULL];
    [archive loadBitmapWithID:302 buffer:_credits_texture_buffer format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED error:NULL];

    glGenTextures(1, &_credits_texture);

    glActiveTexture(GL_TEXTURE0);
    glReportError();
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _credits_texture);
    glReportError();

    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glReportError();

    glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, 360, 784, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _credits_texture_buffer);
    glReportError();

    // set credits state to 1 (first fade-in picture)
    _credits_state = 1;
  } else if (_credits_state == 24) {
    // credits have ended, just return
    return;
  } else {
    // bind the credits texture on image unit 0
    glActiveTexture(GL_TEXTURE0);
    glReportError();
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _credits_texture);
    glReportError();
  }

  // figure out the duration of the current credits state
  double duration;
  if (_credits_state == 1 || _credits_state == 3 || _credits_state == 4 || _credits_state == 6)
    duration = RX_CREDITS_FADE_DURATION;
  else if (_credits_state == 2 || _credits_state == 5)
    duration = RX_CREDITS_STILL_DURATION;
  else
    duration = RX_CREDITS_SCROLLING_DURATION;

  // compute the time interpolation parameter for the current credit state
  float t = RXTimingTimestampDelta(now, _credits_start_time) / duration;

  // start using the card program (we need to do this now because some state
  // transition code needs to set uniforms
  glUseProgram(_card_program);
  glReportError();

  if (_credits_state > 7)
    // if the credit state is > 7, we need to offset time by 0.5 because we
    // begin with the new top page (or the previous bottom page) in the middle
    t += 0.5f;
  else if (_credits_state == 1 || _credits_state == 4)
    // add a negative 1/3 offset to t to delay the beginning of the fade-ins
    t -= 0.33333333f;

  // clamp t to [0.0, 1.0], run state transition code on t > 1.0
  if (t < 0.0f) {
    t = 0.0f;
  } else if (t > 1.0f) {
    // set start time to now and reset t to 0.0
    _credits_start_time = now;
    t = 0.0f;

    if (_credits_state == 1) {
      // next: display 302

      // reset the modulate color on the card program to white
      glUniform4f(_modulate_color_uniform, 1.f, 1.f, 1.f, 1.f);
      glReportError();
    } else if (_credits_state == 2) {
      // next: fade-out 302
    } else if (_credits_state == 3) {
      // next: load 303 and fade-in

      // load 303
      MHKArchive* archive = [[RXArchiveManager sharedArchiveManager] extrasArchive:NULL];
      [archive loadBitmapWithID:303 buffer:_credits_texture_buffer format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED error:NULL];

      glTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, 0, 0, 360, 392, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _credits_texture_buffer);
      glReportError();
    } else if (_credits_state == 4) {
      // next: display 303

      // reset the modulate color on the card program to white
      glUniform4f(_modulate_color_uniform, 1.f, 1.f, 1.f, 1.f);
      glReportError();
    } else if (_credits_state == 5) {
      // next: fade-out 303
    } else if (_credits_state == 6) {
      // next: load 304 and 305 and beging scrolling credits

      // load 304 and 305
      MHKArchive* archive = [[RXArchiveManager sharedArchiveManager] extrasArchive:NULL];
      [archive loadBitmapWithID:304 buffer:_credits_texture_buffer format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED error:NULL];
      [archive loadBitmapWithID:305 buffer:BUFFER_OFFSET(_credits_texture_buffer, 360 * 392 * 4) format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED error:NULL];

      glTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, 0, 0, 360, 784, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _credits_texture_buffer);
      glReportError();

      // reset the modulate color on the card program to white
      glUniform4f(_modulate_color_uniform, 1.f, 1.f, 1.f, 1.f);
      glReportError();
    } else if (_credits_state >= 7) {
      // next: load next scrolling credits page

      // we need to set t to 0.5 (see the comment on if (_credit_state > 7) above)
      t = 0.5f;

      // copy the previous bottom page to the top page
      memcpy(_credits_texture_buffer, BUFFER_OFFSET(_credits_texture_buffer, 360 * 392 * 4), 360 * 392 * 4);

      // load the new bottom page
      if (_credits_state < 22) {
        MHKArchive* archive = [[RXArchiveManager sharedArchiveManager] extrasArchive:NULL];
        [archive loadBitmapWithID:299 + _credits_state
                           buffer:BUFFER_OFFSET(_credits_texture_buffer, 360 * 392 * 4)
                           format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED
                            error:NULL];
      } else {
        memset(BUFFER_OFFSET(_credits_texture_buffer, 360 * 392 * 4), 0, 360 * 392 * 4);
      }

      glTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, 0, 0, 360, 784, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _credits_texture_buffer);
      glReportError();
    } else {
      abort();
    }

    // increment the credit state
    _credits_state++;

    // if we've reached the end of the last credits state, free credits
    // resources and begin a new game
    if (_credits_state == 24) {
      // delete credits resources
      glDeleteTextures(1, &_credits_texture);
      free(_credits_texture_buffer), _credits_texture_buffer = nil;

      // end the credits and begin a new game; note that we'll remain in credit rendering mode
      // until the active card has been cleared but we won't be rendering anything by checking
      // that _credits_state == 24 at the beginning of this method
      // NOTE: we can't use performSelector:withObject:inThread: since the render thread isn't
      //       configured for inter-thread messaging (Tiger support)
      [self performSelectorOnMainThread:@selector(_endCreditsAndBeginNewGame) withObject:nil waitUntilDone:NO];

      return;
    }
  }

  float bottom, top, height;
  if (_credits_state >= 7) {
    height = 784.f;
    top = t * 784.f;
    bottom = top - 784.f;
  } else {
    height = 392.f;
    bottom = 0.0f;
    top = bottom + height;
  }

  float positions[8] = {124.f, bottom, 124.f + 360.f, bottom, 124.f, top, 124.f + 360.f, top};
  float tex_coords[8] = {0.f, height, 360.f, height, 0.f, 0.f, 360.f, 0.f};

  // if we're in one of the fade-in states, we need to set the modulate
  // color to t; conversly, if we're in one of the fade-out states, we need
  // to set the modulate color to 1 - t
  if (_credits_state == 1 || _credits_state == 4) {
    glUniform4f(_modulate_color_uniform, t, t, t, 1.f);
    glReportError();
  } else if (_credits_state == 3 || _credits_state == 6) {
    float one_minus_t = 1.f - t;
    glUniform4f(_modulate_color_uniform, one_minus_t, one_minus_t, one_minus_t, 1.f);
    glReportError();
  }

  // bind VAO 0
  [gl_state bindVertexArrayObject:0];
  glReportError();

  // configure the vertex arrays
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glReportError();

  glEnableVertexAttribArray(RX_ATTRIB_POSITION);
  glReportError();
  glVertexAttribPointer(RX_ATTRIB_POSITION, 2, GL_FLOAT, GL_FALSE, 0, positions);
  glReportError();

  glEnableVertexAttribArray(RX_ATTRIB_TEXCOORD0);
  glReportError();
  glVertexAttribPointer(RX_ATTRIB_TEXCOORD0, 2, GL_FLOAT, GL_FALSE, 0, tex_coords);
  glReportError();

  // enable and configure the scissor test (to clip rendering to the card viewport)
  glEnable(GL_SCISSOR_TEST);
  glScissor(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height);

  // draw the credits quad
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  glReportError();

  // disable the scissor test (Riven X assumption)
  glDisable(GL_SCISSOR_TEST);
}

- (void)render:(const CVTimeStamp*)output_time inContext:(CGLContextObj)cgl_ctx framebuffer:(GLuint)fbo
{
  // WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
  OSSpinLockLock(&_render_lock);

  // alias the render context state object pointer
  NSObject<RXOpenGLStateProtocol>* gl_state = RXGetContextState(cgl_ctx);

  // we need an inner pool within the scope of that lock, or we run the risk
  // of autoreleased enumerators causing objects that should be deallocated on
  // the main thread not to be
  NSAutoreleasePool* p = [NSAutoreleasePool new];

  // end credits mode
  if (_render_credits) {
    [self _renderCredits:cgl_ctx];
    goto exit_render;
  }

  // do nothing if there is no front card
  if (!_front_render_state->card)
    goto exit_render;

  // transition priming
  if (_front_render_state->transition && ![_front_render_state->transition isPrimed]) {
    // bind the transition source texture
    [_transition_source_texture bindWithContext:cgl_ctx lock:NO];

    // bind the dynamic render FBO
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _fbos[RX_CARD_DYNAMIC_RENDER_INDEX]);
    glReportError();

    // copy framebuffer
    glCopyTexSubImage2D(_transition_source_texture->target, 0, 0, 0, 0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height);
    glReportError();

    // give ownership of that texture to the transition
    [_front_render_state->transition primeWithSourceTexture:_transition_source_texture];
  }

  // render the front card
  render_card_imp(self, render_card_sel, output_time, cgl_ctx);

  // final composite (active card + transitions + other special effects)
  glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, fbo);
  glReportError();
  glClear(GL_COLOR_BUFFER_BIT);

  if (_front_render_state->transition && [_front_render_state->transition isPrimed]) {
    // compute the parametric transition parameter based on current time, start time and duration
    float t = [_front_render_state->transition->animation progress];
    if (t > 1.0f)
      t = 1.0f;

    if (t >= 1.0f) {
#if defined(DEBUG)
      RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"transition %@ completed, queue depth=%lu", _front_render_state->transition,
              (unsigned long)[_transitionQueue count]);
#endif
      [_front_render_state->transition release];
      _front_render_state->transition = nil;

      // signal we're no longer running a transition
      semaphore_signal_all(_transitionSemaphore);

      // show the cursor again
      [self showMouseCursor];

      // use the regular rect texture program
      glUseProgram(_card_program);
      glReportError();
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
      glUseProgram(transition->program);
      glReportError();
      glUniform1f(transition->t_uniform, [_front_render_state->transition->animation valueAt:t]);
      glReportError();

      // bind the transition source texture on unit 1
      glActiveTexture(GL_TEXTURE1);
      glReportError();
      [_front_render_state->transition->source_texture bindWithContext:cgl_ctx lock:NO];
    }
  } else {
    glUseProgram(_card_program);
    glReportError();
  }
  // bind the dynamic card content texture to unit 0
  glActiveTexture(GL_TEXTURE0);
  glReportError();
  glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _textures[RX_CARD_DYNAMIC_RENDER_INDEX]);
  glReportError();

  // bind the card composite VAO
  [gl_state bindVertexArrayObject:_card_composite_vao];

  // draw the card composite
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  glReportError();

#if defined(DEBUG)
  if (RXEngineGetBool(@"rendering.marble_lines")) {
    GLfloat attribs[] = {226.f + 16.f,          392.f - 316.f + 66.f,
                         // 246.f + 16.f, 392.f - 263.f + 66,
                         11834.f / 39.f + 16.f, 392.f - 4321.f / 39.f + 66.f, 377.f + 16.f, 392.f - 316.f + 66.f,
                         // 358.f + 16.f, 392.f - 263.f + 66,
                         11834.f / 39.f + 16.f, 392.f - 4321.f / 39.f + 66.f, };

    glUseProgram(0);
    glReportError();
    glColor4f(0.0f, 1.0f, 0.0f, 1.0f);
    glReportError();

    [gl_state bindVertexArrayObject:_debugRenderVAO];
    glReportError();

    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glVertexPointer(2, GL_FLOAT, 0, attribs);
    glReportError();

    glDrawArrays(GL_LINES, 0, 4);
    glReportError();

    [gl_state bindVertexArrayObject:0];
    glReportError();
  }
#endif

exit_render:
  [p release];
  OSSpinLockUnlock(&_render_lock);
}

- (void)renderInMainRT:(CGLContextObj)cgl_ctx
{
  // draw the inventory
  [self _renderInventory:cgl_ctx];

#if defined(DEBUG)
  // alias the render context state object pointer
  NSObject<RXOpenGLStateProtocol>* gl_state = RXGetContextState(cgl_ctx);
  RXCard* front_card = nil;

  BOOL render_hotspots = RXEngineGetBool(@"rendering.hotspots_info");
  BOOL render_cardinfo = RXEngineGetBool(@"rendering.card_info");
  BOOL render_mouseinfo = RXEngineGetBool(@"rendering.mouse_info");
  BOOL render_movieinfo = RXEngineGetBool(@"rendering.movie_info");
  BOOL render_backend = RXEngineGetBool(@"rendering.backend");

  // early bail out if there's nothing to be done
  if (!render_hotspots && !render_cardinfo && !render_mouseinfo && !render_movieinfo && !render_backend)
    return;

  // bind the debug rendering VAO
  [gl_state bindVertexArrayObject:_debugRenderVAO];

  // render hotspots
  if (render_hotspots) {
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

    GLint primitive_index = 0;
    for (RXHotspot* hotspot in activeHotspots) {
      _hotspotDebugRenderFirstElementArray[primitive_index] = primitive_index * 4;
      _hotspotDebugRenderElementCountArray[primitive_index] = 4;

      // get the hotspot's world frame and inset by 0.5 to draw at the pixel center
      // NSRect frame = NSInsetRect([hotspot worldFrame], 0.5, 0.5);
      NSRect frame = [hotspot worldFrame];
      frame.origin.x += 0.5f;
      frame.origin.y -= 0.5f;

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

    uint32_t inv_count = 0;
    if ([[g_world gameState] unsigned32ForKey:@"ainventory"]) {
      for (GLuint inventory_i = 0; inventory_i < RX_MAX_INVENTORY_ITEMS; inventory_i++) {
        if (!(_inventory_flags & (1 << inventory_i)))
          continue;

        _hotspotDebugRenderFirstElementArray[primitive_index] = primitive_index * 4;
        _hotspotDebugRenderElementCountArray[primitive_index] = 4;

        inv_count++;
        NSRect frame = NSInsetRect(_inventory_hotspot_frames[inventory_i], 0.5, 0.5);

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
    }

    glFlushMappedBufferRangeAPPLE(GL_ARRAY_BUFFER, 0, [activeHotspots count] * 24 * sizeof(GLfloat));
    glUnmapBuffer(GL_ARRAY_BUFFER);
    glReportError();

    // configure the VAs
    glVertexPointer(2, GL_FLOAT, 6 * sizeof(GLfloat), NULL);
    glReportError();

    glEnableClientState(GL_COLOR_ARRAY);
    glReportError();
    glColorPointer(4, GL_FLOAT, 6 * sizeof(GLfloat), (void*)BUFFER_OFFSET(NULL, 2 * sizeof(GLfloat)));
    glReportError();

    glMultiDrawArrays(GL_LINE_LOOP, _hotspotDebugRenderFirstElementArray, _hotspotDebugRenderElementCountArray, [activeHotspots count] + inv_count);
    glReportError();

    glDisableClientState(GL_COLOR_ARRAY);
    glReportError();
  }

  // character buffer for debug strings to render
  char debug_buffer[100];

  // VA for the background strip we'll paint before a debug string
  NSPoint background_origin = NSMakePoint(9.5, 19.5);
  GLfloat background_strip[12] = {background_origin.x, background_origin.y,         0.0f, background_origin.x, background_origin.y,         0.0f,
                                  background_origin.x, background_origin.y + 13.0f, 0.0f, background_origin.x, background_origin.y + 13.0f, 0.0f};

  // setup the pipeline to use the client memory VA we defined above
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glVertexPointer(3, GL_FLOAT, 0, background_strip);

  // card info
  if (render_cardinfo) {
    // need to take the render lock to avoid a race condition with the script thread executing a card swap
    if (!front_card) {
      OSSpinLockLock(&_state_swap_lock);
      front_card = [_front_render_state->card retain];
      OSSpinLockUnlock(&_state_swap_lock);
    }

    if (front_card) {
      RXCardDescriptor* desc = [front_card descriptor];
      snprintf(debug_buffer, 100, "card: %s %d [rmap=%u]", [[[desc parent] key] cStringUsingEncoding:NSASCIIStringEncoding], [desc ID], [desc rmap]);

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
  if (render_mouseinfo) {
    NSRect mouse = [self mouseVector];

    float theta = 180.0f * atan2f(mouse.size.height, mouse.size.width) * M_1_PI;
    float r = sqrtf((mouse.size.height * mouse.size.height) + (mouse.size.width * mouse.size.width));

    snprintf(debug_buffer, 100, "mouse vector: (%d, %d) (%.3f, %.3f) (%.3f, %.3f)", (int)mouse.origin.x, (int)mouse.origin.y, mouse.size.width,
             mouse.size.height, theta, r);

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
  if (render_hotspots) {
    OSSpinLockLock(&_state_swap_lock);
    RXHotspot* hotspot = (_current_hotspot >= (RXHotspot*)0x1000) ? [_current_hotspot retain] : _current_hotspot;
    OSSpinLockUnlock(&_state_swap_lock);

    if (hotspot >= (RXHotspot*)0x1000)
      snprintf(debug_buffer, 100, "hotspot: %s", [[hotspot description] cStringUsingEncoding:NSASCIIStringEncoding]);
    else if (hotspot)
      snprintf(debug_buffer, 100, "hotspot: inventory %lu", (uintptr_t)hotspot);
    else
      snprintf(debug_buffer, 100, "hotspot: none");

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

    // go up to the next debug line
    background_origin.y += 13.0;
    background_strip[1] = background_strip[7];
    background_strip[4] = background_strip[7];
    background_strip[7] = background_strip[7] + 13.0f;
    background_strip[10] = background_strip[7];
  }

  // movie info
  if (render_movieinfo) {
    if ([_active_movies count]) {
      RXMovie* movie = [_active_movies objectAtIndex:0];
      NSTimeInterval ct;
      QTGetTimeInterval([movie _noLockCurrentTime], &ct);

      NSTimeInterval duration;
      QTGetTimeInterval([movie duration], &duration);

      snprintf(debug_buffer, 100, "movie display position: %f/%f", ct, duration);
    } else {
      snprintf(debug_buffer, 100, "no active movie");
    }

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

  // backend info
  if (render_backend) {
    snprintf(debug_buffer, 100, "using OpenGL");

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

  // reset the VAO binding to 0 (Riven X assumption)
  [gl_state bindVertexArrayObject:0];

  // release front_card
  [front_card release];
#endif
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime
{
  // WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
  OSSpinLockLock(&_render_lock);

  // we need an inner pool within the scope of that lock, or we run the risk of
  // autoreleased enumerators causing objects that should be deallocated on the
  // main thread not to be
  NSAutoreleasePool* p = [NSAutoreleasePool new];

  // do nothing if there is no front card
  if (!_front_render_state->card)
    goto exit_flush_tasks;

  post_flush_card_imp(self, post_flush_card_sel, outputTime);

exit_flush_tasks:
  [p release];
  OSSpinLockUnlock(&_render_lock);
}

- (void)exportCompositeFramebuffer
{
  CGLContextObj cgl_ctx = [g_worldView loadContext];
  CGLLockContext(cgl_ctx);

  NSBitmapImageRep* image_rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                        pixelsWide:kRXCardViewportSize.width
                                                                        pixelsHigh:kRXCardViewportSize.height
                                                                     bitsPerSample:8
                                                                   samplesPerPixel:4
                                                                          hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                                      bitmapFormat:NSAlphaNonpremultipliedBitmapFormat
                                                                       bytesPerRow:kRXCardViewportSize.width * 4
                                                                      bitsPerPixel:32];

  glActiveTexture(GL_TEXTURE0);
  glReportError();
  glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _textures[RX_CARD_DYNAMIC_RENDER_INDEX]);
  glReportError();
  glGetTexImage(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA, GL_UNSIGNED_INT_8_8_8_8_REV, [image_rep bitmapData]);
  CGLUnlockContext(cgl_ctx);

  OSSpinLockLock(&_state_swap_lock);
  RXCardDescriptor* desc = [[_front_render_state->card descriptor] retain];
  OSSpinLockUnlock(&_state_swap_lock);

  NSString* png_path =
      [[[NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:[desc description]]
          stringByAppendingPathExtension:@"png"];
  NSData* png_data = [image_rep representationUsingType:NSPNGFileType properties:@{}];
  [png_data writeToFile:png_path options:0 error:NULL];

  [desc release];
  [image_rep release];
}

#pragma mark -
#pragma mark user event handling

- (double)mouseTimestamp
{
  OSSpinLockLock(&_mouse_state_lock);
  double t = _mouse_timestamp;
  OSSpinLockUnlock(&_mouse_state_lock);
  return t;
}

- (NSRect)mouseVector
{
  OSSpinLockLock(&_mouse_state_lock);
  NSRect r = _mouse_vector;
  OSSpinLockUnlock(&_mouse_state_lock);
  return r;
}

- (rx_event_t)lastMouseDownEvent
{
  OSSpinLockLock(&_mouse_state_lock);
  rx_event_t e = _last_mouse_down_event;
  OSSpinLockUnlock(&_mouse_state_lock);
  return e;
}

- (void)resetMouseVector
{
  OSSpinLockLock(&_mouse_state_lock);
  if (isfinite(_mouse_vector.size.width)) {
    _mouse_vector.origin.x = _mouse_vector.origin.x + _mouse_vector.size.width;
    _mouse_vector.origin.y = _mouse_vector.origin.y + _mouse_vector.size.height;
    _mouse_vector.size.width = 0.0;
    _mouse_vector.size.height = 0.0;
  }
  OSSpinLockUnlock(&_mouse_state_lock);
}

- (void)showMouseCursor
{
  [self enableHotspotHandling];

  int32_t updated_counter = OSAtomicDecrement32Barrier(&_cursor_hide_counter);
  release_assert(updated_counter >= 0);
#if defined(DEBUG) && DEBUG > 1
  RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"showMouseCursor; counter=%d", updated_counter);
#endif

  if (updated_counter == 0) {
    // if the hotspot handling disable counter is at 0, updateHotspotState
    // ran and updated the cursor; so if it's > 0, we need to restore the backup
    if (_hotspot_handling_disable_counter > 0)
      [g_worldView setCursor:_hidden_cursor];

    [_hidden_cursor release], _hidden_cursor = nil;
  }
}

- (void)hideMouseCursor
{
  [self disableHotspotHandling];

  int32_t updated_counter = OSAtomicIncrement32Barrier(&_cursor_hide_counter);
  release_assert(updated_counter >= 0);
#if defined(DEBUG) && DEBUG > 1
  RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"hideMouseCursor; counter=%d", updated_counter);
#endif

  if (updated_counter == 1) {
    _hidden_cursor = [[g_worldView cursor] retain];
    [g_worldView setCursor:[g_world invisibleCursor]];
  }
}

- (void)setMouseCursor:(uint16_t)cursorID
{
  NSCursor* new_cursor = [g_world cursorForID:cursorID];
  if (_cursor_hide_counter > 0) {
    id old = _hidden_cursor;
    _hidden_cursor = [new_cursor retain];
    [old release];
  } else {
    [g_worldView setCursor:new_cursor];
  }
}

- (void)enableHotspotHandling
{
  int32_t updated_counter = OSAtomicDecrement32Barrier(&_hotspot_handling_disable_counter);
  release_assert(updated_counter >= 0);

  if (updated_counter == 0)
    [self updateHotspotState];
}

- (void)disableHotspotHandling
{
  int32_t updated_counter = OSAtomicIncrement32Barrier(&_hotspot_handling_disable_counter);
  release_assert(updated_counter >= 0);

  if (updated_counter == 1)
    [self updateHotspotState];
}

- (void)_updateHotspotState_nolock
{
  // WARNING: MUST RUN ON THE MAIN THREAD
  if (!pthread_main_np())
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_updateHotspotState_nolock: MUST RUN ON MAIN THREAD" userInfo:nil];

  // get the mouse vector using the getter since it will take the spin lock and return a copy
  NSRect mouse_vector = [self mouseVector];

  // get the front card's active hotspots
  NSArray* active_hotspots = [sengine activeHotspots];

  // update the active status of the inventory based on the position of the mouse
  if (NSMouseInRect(mouse_vector.origin, [(NSView*)g_worldView bounds], NO) && mouse_vector.origin.y < kRXInventorySize.height)
    _inventory_has_focus = YES;
  else
    _inventory_has_focus = NO;

  // find over which hotspot the mouse is
  RXHotspot* hotspot = nil;
  for (hotspot in active_hotspots) {
    if (NSMouseInRect(mouse_vector.origin, [hotspot worldFrame], NO))
      break;
  }

  // now check if we're over one of the inventory regions
  if (!hotspot) {
    OSSpinLockLock(&_inventory_update_lock);
    if ([[g_world gameState] unsigned32ForKey:@"ainventory"] && _inventory_flags) {
      for (GLuint inventory_i = 0; inventory_i < RX_MAX_INVENTORY_ITEMS; inventory_i++) {
        if (!(_inventory_flags & (1 << inventory_i)))
          continue;

        if (NSMouseInRect(mouse_vector.origin, _inventory_hotspot_frames[inventory_i], NO)) {
          // set hotspot to the inventory item index (plus one to avoid the value 0); the following block of code
          // will check if hotspot is not 0 and below PAGEZERO, and act accordingly
          hotspot = (RXHotspot*)(inventory_i + 1);
          break;
        }
      }
    }
    OSSpinLockUnlock(&_inventory_update_lock);
  }

  // if the new current hotspot is valid, matches the mouse down hotspot and the mouse is not dragging, we need to send
  // a mouse up message to the hotspot
  if (hotspot >= (RXHotspot*)0x1000 && hotspot == _mouse_down_hotspot && isinf(mouse_vector.size.width)) {
    // reset the mouse down hotspot
    [_mouse_down_hotspot release];
    _mouse_down_hotspot = nil;

    // disable hotspot handling; the script engine is responsible for re-enabling it
    [self disableHotspotHandling];

    // set the event of the hotspot so that the script engine knows where the event occurred
    rx_event_t event = {_mouse_vector.origin, _mouse_timestamp};
    [hotspot setEvent:event];

    // let the script engine run mouse up scripts
    [sengine performSelector:@selector(mouseUpInHotspot:) withObject:hotspot inThread:[g_world scriptThread]];
  }

  // if the old current hotspot is valid, doesn't match the new current hotspot and is still active, we need to send the old
  // current hotspot a mouse exited message
  if (_current_hotspot >= (RXHotspot*)0x1000 && _current_hotspot != hotspot && [active_hotspots indexOfObjectIdenticalTo:_current_hotspot] != NSNotFound) {
    // note that we DO NOT disable hotspot handling for "exited hotspot" messages
    [sengine performSelector:@selector(mouseExitedHotspot:) withObject:_current_hotspot inThread:[g_world scriptThread]];
  }

  // handle cursor changes here so we don't ping-pong across 2 threads (at least for a hotspot's cursor, the inventory item
  // cursor and the default cursor)
  if (hotspot == 0) {
    [g_worldView setCursor:[g_world defaultCursor]];
  } else if (hotspot < (RXHotspot*)0x1000) {
    [g_worldView setCursor:[g_world openHandCursor]];
  } else {
    [g_worldView setCursor:[g_world cursorForID:[hotspot cursorID]]];

    // valid hotspots receive periodic "inside hotspot" messages when the mouse is not dragging; note that we do NOT disable
    // hotspot handling for "inside hotspot" messages
    if (isinf(mouse_vector.size.width))
      [sengine performSelector:@selector(mouseInsideHotspot:) withObject:hotspot inThread:[g_world scriptThread]];
  }

  // update the current hotspot to the new current hotspot
  if (_current_hotspot != hotspot) {
    id old = _current_hotspot;

    if (hotspot >= (RXHotspot*)0x1000)
      _current_hotspot = [hotspot retain];
    else
      _current_hotspot = hotspot;

    if (old >= (RXHotspot*)0x1000)
      [old release];
  }
}

- (void)updateHotspotState
{
  // NOTE: this method must run on the main thread and will bounce itself there if needed
  if (!pthread_main_np()) {
    [self performSelectorOnMainThread:@selector(updateHotspotState) withObject:nil waitUntilDone:NO];
    return;
  }

  // when we're on edge values of the hotspot handling disable counter, we need to update the load / save UI
  // (because it basically means we're starting to execute some script as a response of user action)
  if (_hotspot_handling_disable_counter == 0)
    [[RXApplicationDelegate sharedApplicationDelegate] setDisableGameLoadingAndSaving:NO];
  else if (_hotspot_handling_disable_counter == 1)
    [[RXApplicationDelegate sharedApplicationDelegate] setDisableGameLoadingAndSaving:YES];

  // if hotspot handling is disabled, simply return
  if (_hotspot_handling_disable_counter > 0)
    return;

  // hotspot updates cannot occur during a card switch
  auto_spinlock state_lock(&_state_swap_lock);

  // check if hotspot handling is disabled again (last time, this is only to handle the situation where we might have slept a little while on the spin lock
  if (_hotspot_handling_disable_counter > 0)
    return;

  [self _updateHotspotState_nolock];
}

- (void)_handleInventoryMouseDownWithItemIndex:(uint32_t)index
{
  // WARNING: this method assumes the state swap lock has been taken by the caller

  if (index >= RX_MAX_INVENTORY_ITEMS)
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"OUT OF BOUNDS INVENTORY INDEX" userInfo:nil];

  RXStack* stack = [g_world loadStackWithKey:@"aspit"];
  if (!stack) {
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelError, @"aborting _handleInventoryMouseDown because stack aspit could not be loaded");
    return;
  }

  uint16_t journal_card_id = [stack cardIDFromRMAPCode:RX_INVENTORY_RMAPS[index]];
  if (!journal_card_id) {
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelError, @"aborting _handleInventoryMouseDown because card rmap %u could not be resolved",
            RX_INVENTORY_RMAPS[index]);
    return;
  }

  // disable the inventory
  [[g_world gameState] setUnsigned32:0 forKey:@"ainventory"];

  // set the return card in the game state to the current card; need to take the render lock to avoid a race condition
  // with the script thread executing a card swap
  [[g_world gameState] setReturnCard:[[_front_render_state->card descriptor] simpleDescriptor]];

  // schedule a cross-fade transition to the journal card
  RXTransition* transition =
      [[RXTransition alloc] initWithType:RXTransitionDissolve direction:0 region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
  [self queueTransition:transition];
  [transition release];

  // activate an empty sound group with fade out to fade out the current card's ambient sounds
  RXSoundGroup* sgroup = [RXSoundGroup new];
  sgroup->gain = 1.0f;
  sgroup->loop = NO;
  sgroup->fadeOutRemovedSounds = YES;
  sgroup->fadeInNewSounds = NO;
  [self performSelector:@selector(activateSoundGroup:) withObject:sgroup inThread:[g_world scriptThread] waitUntilDone:NO];
  [sgroup release];

  // leave ourselves a note to force a fade in on the next activate sound group command
  _forceFadeInOnNextSoundGroup = YES;

  // change the active card to the journal card
  [self setActiveCardWithStack:@"aspit" ID:journal_card_id waitUntilDone:NO];
}

- (void)mouseMoved:(NSEvent*)event
{
  NSPoint mousePoint = [(NSView*)g_worldView convertPoint:[event locationInWindow] fromView:nil];

  // update the mouse vector
  OSSpinLockLock(&_mouse_state_lock);
  _mouse_vector.origin = mousePoint;
  _mouse_timestamp = [event timestamp];
  OSSpinLockUnlock(&_mouse_state_lock);

  // update the hotspot state
  [self updateHotspotState];
}

- (void)mouseDragged:(NSEvent*)event
{
  NSPoint mousePoint = [(NSView*)g_worldView convertPoint:[event locationInWindow] fromView:nil];

  // update the mouse vector
  OSSpinLockLock(&_mouse_state_lock);
  _mouse_vector.size.width = mousePoint.x - _mouse_vector.origin.x;
  _mouse_vector.size.height = mousePoint.y - _mouse_vector.origin.y;
  _mouse_timestamp = [event timestamp];
  OSSpinLockUnlock(&_mouse_state_lock);

  // update the hotspot state
  [self updateHotspotState];
}

- (void)_performMouseDown
{
  // if the current hotspot is valid, send it a mouse down event; if the current "hotspot" is an inventory item, handle that too
  if (_current_hotspot >= (RXHotspot*)0x1000) {
    // remember the last hotspot for which we've sent a "mouse down" message
    _mouse_down_hotspot = [_current_hotspot retain];

    // set the event of the current hotspot so that the script engine knows where the mouse down occurred
    [_current_hotspot setEvent:_last_mouse_down_event];

    // disable hotspot handling; the script engine is responsible for re-enabling it
    [self disableHotspotHandling];

    // let the script engine run mouse down scripts
    [sengine performSelector:@selector(mouseDownInHotspot:) withObject:_current_hotspot inThread:[g_world scriptThread]];
  } else if (_current_hotspot) {
    [self _handleInventoryMouseDownWithItemIndex:(uintptr_t)_current_hotspot - 1];
  }

  // we do not need to call updateHotspotState from mouse down, since handling inventory hotspots would be difficult there
  // (can't retain a non-valid pointer value, e.g. can't store the dummy _current_hotspot value into _mouse_down_hotspot
}

- (void)mouseDown:(NSEvent*)event
{
  NSPoint mouse_point = [(NSView*)g_worldView convertPoint:[event locationInWindow] fromView:nil];

  // update the mouse vector
  OSSpinLockLock(&_mouse_state_lock);
  _mouse_vector.origin = mouse_point;
  _mouse_vector.size = NSZeroSize;
  _mouse_timestamp = [event timestamp];

  _last_mouse_down_event.location = _mouse_vector.origin;
  _last_mouse_down_event.timestamp = _mouse_timestamp;
  OSSpinLockUnlock(&_mouse_state_lock);

  // if hotspot handling is disabled, simply return
  if (_hotspot_handling_disable_counter > 0)
    return;

  // cannot use the front card during state swaps
  auto_spinlock state_lock(&_state_swap_lock);

  // perform the mouse down
  [self _performMouseDown];
}

- (void)mouseUp:(NSEvent*)event
{
  // update the mouse vector
  OSSpinLockLock(&_mouse_state_lock);
  _mouse_vector.origin = [(NSView*)g_worldView convertPoint:[event locationInWindow] fromView:nil];
  _mouse_vector.size.width = INFINITY;
  _mouse_vector.size.height = INFINITY;
  _mouse_timestamp = [event timestamp];
  OSSpinLockUnlock(&_mouse_state_lock);

  // if hotspot handling is disabled, simply return
  if (_hotspot_handling_disable_counter > 0)
    return;

  // finally we need to update the hotspot state; updateHotspotState will take care of sending the mouse up event if there is a
  // mouse down hotspot and the mouse is still over that hotspot
  [self updateHotspotState];
}

- (BOOL)_isMouseOverHotspot:(RXHotspot*)desired_hotspot activeHotspots:(NSArray*)active_hotspots mouseLocation:(NSPoint)mouse_origin
{
  RXHotspot* hotspot = nil;
  for (hotspot in active_hotspots) {
    if (NSMouseInRect(mouse_origin, [hotspot worldFrame], NO))
      break;
  }

  return (hotspot == desired_hotspot) ? YES : NO;
}

- (void)swipeWithEvent:(NSEvent*)event
{
  NSRect mouse_vector = [self mouseVector];

  // if hotspot handling is disabled or the mouse is down, do nothing
  BOOL mouse_down = isfinite(mouse_vector.size.width);

  if (_hotspot_handling_disable_counter > 0 || mouse_down)
    return;

  // based on the swipe direction, look up one of the standard movement hotspots in the active set and generate a "mouse down" event if we find one
  NSArray* eligible_names;
  if ([event deltaX] < 0.0)
    eligible_names = [NSArray arrayWithObjects:@"right", @"afr", nil];
  else if ([event deltaX] > 0.0)
    eligible_names = [NSArray arrayWithObjects:@"left", @"afl", nil];
  else if ([event deltaY] < 0.0)
    eligible_names = [NSArray arrayWithObjects:@"down", nil];
  else if ([event deltaY] > 0.0)
    eligible_names = [NSArray arrayWithObjects:@"up", nil];
  else
    eligible_names = nil;

#if defined(DEBUG)
  RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"swipe %@", event);
#endif

  // if we didn't recognize the swipe direction, we're done
  if (eligible_names == nil)
    return;

  // so, to guarantee that we're going to maintain a consistent state in Riven X, we'll need to pretend that the mouse has moved over the eligible hotspot
  // moused down on it, then moused up, all within the rules of how events are handled; moving the mouse as such implies running the mouse exited handler
  // of the current hotspot, doing the work, then figuring out what is under the mouse after the swipe and running a mouse entered handler if it is over
  // a hotspot

  // cannot use the front card during state swaps
  auto_spinlock state_lock(&_state_swap_lock);

  // check if hotspot handling is disabled again (last time, this is only to handle the situation where we might have slept a little while on the spin lock
  if (_hotspot_handling_disable_counter > 0)
    return;

  // try to find an eligible hotspot
  RXHotspot* swipe_hotspot = nil;
  for (NSString* name in eligible_names) {
    swipe_hotspot = [sengine activeHotspotWithName:name];
    if (swipe_hotspot)
      break;
  }

  // if we did not find any eligible hotspot, we're done
  if (swipe_hotspot == nil)
    return;

  // instant-move the mouse inside of the chosen hotspot; we do this by finding a mouse location that will put the cursor over the eligile hotspot

  // get the frame for the target hotspot
  NSRect hotspot_frame = [swipe_hotspot worldFrame];

  // get the front card's active hotspots
  NSArray* active_hotspots = [sengine activeHotspots];

  // find a swipe origin that will put the cursor over the swipe hotspot

  // bottom left corner
  NSPoint swipe_origin = NSMakePoint(hotspot_frame.origin.x, hotspot_frame.origin.y + 1.0);
  BOOL in_swipe_hotspot = [self _isMouseOverHotspot:swipe_hotspot activeHotspots:active_hotspots mouseLocation:swipe_origin];
  if (!in_swipe_hotspot) {
    // top left corner
    swipe_origin = NSMakePoint(hotspot_frame.origin.x + hotspot_frame.size.width - 1.0, hotspot_frame.origin.y + 1.0);
    in_swipe_hotspot = [self _isMouseOverHotspot:swipe_hotspot activeHotspots:active_hotspots mouseLocation:swipe_origin];

    if (!in_swipe_hotspot) {
      // bottom right corner
      swipe_origin = NSMakePoint(hotspot_frame.origin.x, hotspot_frame.origin.y + hotspot_frame.size.height);
      in_swipe_hotspot = [self _isMouseOverHotspot:swipe_hotspot activeHotspots:active_hotspots mouseLocation:swipe_origin];

      if (!in_swipe_hotspot) {
        // top right corner
        swipe_origin = NSMakePoint(hotspot_frame.origin.x + hotspot_frame.size.width - 1.0, hotspot_frame.origin.y + hotspot_frame.size.height);
        in_swipe_hotspot = [self _isMouseOverHotspot:swipe_hotspot activeHotspots:active_hotspots mouseLocation:swipe_origin];

        if (!in_swipe_hotspot) {
          // center
          swipe_origin = NSMakePoint(hotspot_frame.origin.x + (hotspot_frame.size.width / 2.0), hotspot_frame.origin.y + (hotspot_frame.size.height / 2.0));
          in_swipe_hotspot = [self _isMouseOverHotspot:swipe_hotspot activeHotspots:active_hotspots mouseLocation:swipe_origin];

          // give up at this point
        }
      }
    }
  }

  // if we did not find a location where the mouse is over the swipe hotspot, we're done :(
  if (!in_swipe_hotspot)
    return;

  NSRect previous_mouse_vector;
  {
    auto_spinlock mouse_lock(&_mouse_state_lock);

    // we need to copy the current mouse vector to restore it after the swipe
    previous_mouse_vector = _mouse_vector;

    _mouse_vector.origin = swipe_origin;
    _mouse_vector.size.width = INFINITY;
    _mouse_vector.size.height = INFINITY;
    _mouse_timestamp = [event timestamp];
  }

  // hide the mouse cursor to avoid the cursor flashing as we artificially move the cursor around
  [self hideMouseCursor];

  // updateHotspotState will take care of sending the mouse up event if there is a mouse down hotspot and the mouse is still over that hotspot; we use the
  // _nolock version here because we've already taken the state swap lock
  [self _updateHotspotState_nolock];

  // we can now finally generate a mouse down event; we do this by changing the mouse vector's size from INFINITY to zero
  {
    auto_spinlock mouse_lock(&_mouse_state_lock);
    _mouse_vector.size = NSZeroSize;
  }

  // perform the mouse down
  [self _performMouseDown];

  // restore the mouse's position
  {
    auto_spinlock mouse_lock(&_mouse_state_lock);
    _mouse_vector = previous_mouse_vector;
  }

  // update the hotspot state again
  [self _updateHotspotState_nolock];

  // balance the hideMouseCursor done above
  [self showMouseCursor];
}

- (void)keyDown:(NSEvent*)event
{
  NSString* characters = [event charactersIgnoringModifiers];
  if (![event isARepeat] && [characters isEqualToString:@" "])
    [sengine skipBlockingMovie];
}

- (void)_handleWindowDidBecomeKey:(NSNotification*)notification
{
  // FIXME: there may be a time-sensitive crash lurking around here

  NSWindow* window = [notification object];
  if (window == [g_worldView window]) {
    // update the mouse vector
    OSSpinLockLock(&_mouse_state_lock);
    _mouse_vector.origin = [(NSView*)g_worldView convertPoint:[[(NSView*)g_worldView window] mouseLocationOutsideOfEventStream] fromView:nil];
    _mouse_vector.size.width = INFINITY;
    _mouse_vector.size.height = INFINITY;
    OSSpinLockUnlock(&_mouse_state_lock);

    // update the hotspot state
    [self updateHotspotState];
  }
}

- (void)_handleWindowDidResignKey:(NSNotification*)notification {}

@end
