//
//  RXScriptEngine.m
//  rivenx
//
//  Created by Jean-Francois Roy on 31/01/2009.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import <assert.h>
#import <limits.h>

#import <mach/task.h>
#import <mach/thread_act.h>
#import <mach/thread_policy.h>

#import <objc/runtime.h>

#import "Rendering/RXRendering.h"

#import "Base/RXTiming.h"

#import "Engine/RXScriptDecoding.h"
#import "Engine/RXScriptEngine.h"
#import "Engine/RXScriptCommandAliases.h"
#import "Engine/RXWorldProtocol.h"
#import "Engine/RXArchiveManager.h"
#import "Engine/RXCursors.h"

#import "Rendering/Graphics/RXTextureBroker.h"
#import "Rendering/Graphics/RXTransition.h"
#import "Rendering/Graphics/RXDynamicPicture.h"

#import "Utilities/random.h"

#import "Application/RXApplicationDelegate.h"

static useconds_t const kRunloopPeriodMicroseconds = 1000;

static double const kRXLinkingBookDelay = 1.4;

static uint32_t const sunners_upper_stairs_rmap = 30678;
static uint32_t const sunners_mid_stairs_rmap = 31165;
static uint32_t const sunners_lower_stairs_rmap = 31723;
static uint32_t const sunners_beach_rmap = 46794;

typedef void (*rx_command_imp_t)(id, SEL, const uint16_t, const uint16_t*);
struct _rx_command_dispatch_entry {
  rx_command_imp_t imp;
  SEL sel;
};
typedef struct _rx_command_dispatch_entry rx_command_dispatch_entry_t;

#define RX_COMMAND_COUNT 48
static rx_command_dispatch_entry_t _riven_command_dispatch_table[RX_COMMAND_COUNT];
static NSMapTable* _riven_external_command_dispatch_map;

#define DEFINE_COMMAND(NAME) -(void)_external_##NAME : (const uint16_t)argc arguments : (const uint16_t*)argv
#define COMMAND_SELECTOR(NAME) @selector(_external_##NAME:arguments:)

RX_INLINE void rx_dispatch_commandv(id target, rx_command_dispatch_entry_t* command, uint16_t argc, uint16_t* argv)
{ command->imp(target, command->sel, argc, argv); }

RX_INLINE void rx_dispatch_command0(id target, rx_command_dispatch_entry_t* command)
{
  uint16_t args;
  rx_dispatch_commandv(target, command, 0, &args);
}

RX_INLINE void rx_dispatch_command1(id target, rx_command_dispatch_entry_t* command, uint16_t a1)
{
  uint16_t args[] = {a1};
  rx_dispatch_commandv(target, command, 1, args);
}

RX_INLINE void rx_dispatch_command2(id target, rx_command_dispatch_entry_t* command, uint16_t a1, uint16_t a2)
{
  uint16_t args[] = {a1, a2};
  rx_dispatch_commandv(target, command, 2, args);
}

RX_INLINE void rx_dispatch_command3(id target, rx_command_dispatch_entry_t* command, uint16_t a1, uint16_t a2, uint16_t a3)
{
  uint16_t args[] = {a1, a2, a3};
  rx_dispatch_commandv(target, command, 3, args);
}

#define DISPATCH_COMMANDV(COMMAND_INDEX, ARGC, ARGV) rx_dispatch_commandv(self, _riven_command_dispatch_table + COMMAND_INDEX, ARGC, ARGV)
#define DISPATCH_COMMAND0(COMMAND_INDEX) rx_dispatch_command0(self, _riven_command_dispatch_table + COMMAND_INDEX)
#define DISPATCH_COMMAND1(COMMAND_INDEX, ARG1) rx_dispatch_command1(self, _riven_command_dispatch_table + COMMAND_INDEX, ARG1)
#define DISPATCH_COMMAND2(COMMAND_INDEX, ARG1, ARG2) rx_dispatch_command2(self, _riven_command_dispatch_table + COMMAND_INDEX, ARG1, ARG2)
#define DISPATCH_COMMAND3(COMMAND_INDEX, ARG1, ARG2, ARG3) rx_dispatch_command3(self, _riven_command_dispatch_table + COMMAND_INDEX, ARG1, ARG2, ARG3)

RX_INLINE void rx_dispatch_externalv(id target, NSString* external_name, uint16_t argc, uint16_t* argv)
{
  rx_command_dispatch_entry_t* command = (rx_command_dispatch_entry_t*)NSMapGet(_riven_external_command_dispatch_map, [external_name lowercaseString]);
  command->imp(target, command->sel, argc, argv);
}

RX_INLINE void rx_dispatch_external1(id target, NSString* external_name, uint16_t a1)
{
  uint16_t args[] = {a1};
  rx_dispatch_externalv(target, external_name, 1, args);
}

@implementation RXScriptEngine

+ (void)initialize
{
  static BOOL initialized = NO;
  if (initialized)
    return;
  initialized = YES;

// build the principal command dispatch table
#pragma mark opcode dispatch table
  _riven_command_dispatch_table[0].sel = @selector(_invalid_opcode:arguments:); // may be a valid command (draw back bitmap)
  _riven_command_dispatch_table[1].sel = @selector(_opcode_drawDynamicPicture:arguments:);
  _riven_command_dispatch_table[2].sel = @selector(_opcode_goToCard:arguments:);
  _riven_command_dispatch_table[3].sel = @selector(_opcode_activateSynthesizedSLST:arguments:);
  _riven_command_dispatch_table[4].sel = @selector(_opcode_playDataSound:arguments:);
  _riven_command_dispatch_table[5].sel = @selector(_opcode_activateSynthesizedMLST:arguments:);
  _riven_command_dispatch_table[6].sel = @selector(_opcode_unimplemented:arguments:); // is complex animate command
  _riven_command_dispatch_table[7].sel = @selector(_opcode_setVariable:arguments:);
  _riven_command_dispatch_table[8].sel = @selector(_invalid_opcode:arguments:);
  _riven_command_dispatch_table[9].sel = @selector(_opcode_enableHotspot:arguments:);
  _riven_command_dispatch_table[10].sel = @selector(_opcode_disableHotspot:arguments:);
  _riven_command_dispatch_table[11].sel = @selector(_invalid_opcode:arguments:);
  _riven_command_dispatch_table[12].sel = @selector(_opcode_clearSounds:arguments:);
  _riven_command_dispatch_table[13].sel = @selector(_opcode_setCursor:arguments:);
  _riven_command_dispatch_table[14].sel = @selector(_opcode_pause:arguments:);
  _riven_command_dispatch_table[15].sel = @selector(_invalid_opcode:arguments:);
  _riven_command_dispatch_table[16].sel = @selector(_invalid_opcode:arguments:);
  _riven_command_dispatch_table[17].sel = @selector(_opcode_callExternal:arguments:);
  _riven_command_dispatch_table[18].sel = @selector(_opcode_scheduleTransition:arguments:);
  _riven_command_dispatch_table[19].sel = @selector(_opcode_reloadCard:arguments:);
  _riven_command_dispatch_table[20].sel = @selector(_opcode_disableScreenUpdates:arguments:);
  _riven_command_dispatch_table[21].sel = @selector(_opcode_enableScreenUpdates:arguments:);
  _riven_command_dispatch_table[22].sel = @selector(_invalid_opcode:arguments:);
  _riven_command_dispatch_table[23].sel = @selector(_invalid_opcode:arguments:);
  _riven_command_dispatch_table[24].sel = @selector(_opcode_incrementVariable:arguments:);
  _riven_command_dispatch_table[25].sel = @selector(_opcode_decrementVariable:arguments:);
  _riven_command_dispatch_table[26].sel = @selector(_opcode_closeAllMovies:arguments:);
  _riven_command_dispatch_table[27].sel = @selector(_opcode_goToStack:arguments:);
  _riven_command_dispatch_table[28].sel = @selector(_opcode_disableMovie:arguments:);
  _riven_command_dispatch_table[29].sel = @selector(_opcode_disableAllMovies:arguments:);
  _riven_command_dispatch_table[30].sel = @selector(_opcode_unimplemented:arguments:); // is "set movie rate", given movie code
  _riven_command_dispatch_table[31].sel = @selector(_opcode_enableMovie:arguments:);
  _riven_command_dispatch_table[32].sel = @selector(_opcode_startMovieAndWaitUntilDone:arguments:);
  _riven_command_dispatch_table[33].sel = @selector(_opcode_startMovie:arguments:);
  _riven_command_dispatch_table[34].sel = @selector(_opcode_stopMovie:arguments:);
  _riven_command_dispatch_table[35].sel = @selector(_opcode_unimplemented:arguments:); // activate SFXE (arg0 is the SFXE ID)
  _riven_command_dispatch_table[36].sel = @selector(_opcode_noop:arguments:);
  _riven_command_dispatch_table[37].sel = @selector(_opcode_fadeAmbientSounds:arguments:);
  _riven_command_dispatch_table[38].sel = @selector(_opcode_scheduleMovieCommand:arguments:);
  _riven_command_dispatch_table[39].sel = @selector(_opcode_activatePLST:arguments:);
  _riven_command_dispatch_table[40].sel = @selector(_opcode_activateSLST:arguments:);
  _riven_command_dispatch_table[41].sel = @selector(_opcode_activateMLSTAndStartMovie:arguments:);
  _riven_command_dispatch_table[42].sel = @selector(_opcode_noop:arguments:);
  _riven_command_dispatch_table[43].sel = @selector(_opcode_activateBLST:arguments:);
  _riven_command_dispatch_table[44].sel = @selector(_opcode_activateFLST:arguments:);
  _riven_command_dispatch_table[45].sel = @selector(_opcode_unimplemented:arguments:); // is "do zip"
  _riven_command_dispatch_table[46].sel = @selector(_opcode_activateMLST:arguments:);
  _riven_command_dispatch_table[47].sel = @selector(_opcode_activateSLSTWithVolume:arguments:);

  for (unsigned char selectorIndex = 0; selectorIndex < RX_COMMAND_COUNT; selectorIndex++)
    _riven_command_dispatch_table[selectorIndex].imp = (rx_command_imp_t)[self instanceMethodForSelector : _riven_command_dispatch_table[selectorIndex].sel];

  // search for external command implementation methods and register them
  _riven_external_command_dispatch_map = NSCreateMapTable(NSObjectMapKeyCallBacks, NSNonRetainedObjectMapValueCallBacks, 0);

  NSCharacterSet* colon_character_set = [NSCharacterSet characterSetWithCharactersInString:@":"];

  /*
      void* iterator = 0;
      struct objc_method_list* mlist;
      while ((mlist = class_nextMethodList(self, &iterator))) {
          for (int method_index = 0; method_index < mlist->method_count; method_index++) {
              Method m = mlist->method_list + method_index;
              NSString* method_selector_string = NSStringFromSelector(m->method_name);
              if ([method_selector_string hasPrefix:@"_external_"]) {
                  NSRange first_colon_range = [method_selector_string rangeOfCharacterFromSet:colon_character_set options:NSLiteralSearch];
                  NSString* external_name = [[method_selector_string substringWithRange:NSMakeRange([(NSString*)@"_external_" length],
                                                                                                    first_colon_range.location - [(NSString*)@"_external_"
  length])]
                                             lowercaseString];
  #if defined(DEBUG) && DEBUG > 1
                  RXLog(kRXLoggingEngine, kRXLoggingLevelDebug, @"registering external command: %@", external_name);
  #endif
                  rx_command_dispatch_entry_t* command_dispatch = (rx_command_dispatch_entry_t*)malloc(sizeof(rx_command_dispatch_entry_t));
                  command_dispatch->sel = m->method_name;
                  command_dispatch->imp = (rx_command_imp_t)m->method_imp;
                  NSMapInsertKnownAbsent(_riven_external_command_dispatch_map, external_name, command_dispatch);
              }
          }
      }
  */
  uint32_t mlist_count;
  Method* mlist = class_copyMethodList(self, &mlist_count);
  for (uint32_t method_index = 0; method_index < mlist_count; ++method_index) {
    Method m = mlist[method_index];
    SEL m_sel = method_getName(m);
    NSString* method_selector_string = NSStringFromSelector(m_sel);
    if ([method_selector_string hasPrefix:@"_external_"]) {
      NSRange first_colon_range = [method_selector_string rangeOfCharacterFromSet:colon_character_set options:NSLiteralSearch];
      NSRange range = NSMakeRange([(NSString*)@"_external_" length], first_colon_range.location - [(NSString*)@"_external_" length]);
      NSString* external_name = [[method_selector_string substringWithRange:range] lowercaseString];
#if defined(DEBUG) && DEBUG > 1
      RXLog(kRXLoggingEngine, kRXLoggingLevelDebug, @"registering external command: %@", external_name);
#endif
      rx_command_dispatch_entry_t* command_dispatch = (rx_command_dispatch_entry_t*)malloc(sizeof(rx_command_dispatch_entry_t));
      command_dispatch->sel = m_sel;
      command_dispatch->imp = (rx_command_imp_t)method_getImplementation(m);
      NSMapInsertKnownAbsent(_riven_external_command_dispatch_map, external_name, command_dispatch);
    }
  }
  free(mlist);
}

+ (BOOL)accessInstanceVariablesDirectly { return NO; }

- (id)init
{
  [self doesNotRecognizeSelector:_cmd];
  [self release];
  return nil;
}

- (id)initWithController:(id<RXScriptEngineControllerProtocol>)ctlr
{
  self = [super init];
  if (!self)
    return nil;

  controller = ctlr;

  _card_lock = OS_SPINLOCK_INIT;

  logPrefix = [NSMutableString new];

  _active_hotspots_lock = OS_SPINLOCK_INIT;
  _active_hotspots = [NSMutableArray new];

  _dynamic_texture_cache = [NSMutableDictionary new];
  _picture_cache = [NSMutableDictionary new];

  code_movie_map = NSCreateMapTable(NSIntegerMapKeyCallBacks, NSObjectMapValueCallBacks, 0);
  _movies_to_reset = [NSMutableSet new];

  _screen_update_disable_counter = 0;

  // initialize gameplay support variables

  // sliders are packed to the left
  sliders_state = 0x1F00000;

  // default dome slider background display origin
  dome_slider_background_position.x = 200;
  dome_slider_background_position.y = 250;

  // the trapeze rect is emcompasses the bottom part of the trapeze on jspit 276
  trapeze_rect = NSMakeRect(295, 251, 16, 36);

  // register for movie rate change notifications
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_handleBlockingMovieFinishedPlaying:)
                                               name:RXMoviePlaybackDidEndNotification
                                             object:nil];

  // register for game state loaded notifications o we can reset ourselves properly
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleGameStateLoaded:) name:@"RXGameStateLoadedNotification" object:nil];

  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [cath_prison_scdesc release];
  [rebel_prison_window_scdesc release];
  [frog_trap_scdesc release];
  [whark_solo_card release];

  [_movies_to_reset release];
  if (code_movie_map)
    NSFreeMapTable(code_movie_map);

  [_picture_cache release];
  [_dynamic_texture_cache release];

  [_active_hotspots release];

  [_synthesizedSoundGroup release];
  [_card release];

  [logPrefix release];

  [super dealloc];
}

#pragma mark -
#pragma mark game state

- (void)_handleGameStateLoaded:(NSNotification*)notification
{
  RXGameState* gs = [g_world gameState];

  played_one_whark_solo = [gs unsigned32ForKey:@"played_one_whark_solo"];

  intro_scheduled_atrus_give_books = [gs unsigned32ForKey:@"intro_scheduled_atrus_give_books"];
  intro_atrus_gave_books = [gs unsigned32ForKey:@"intro_atrus_gave_books"];
  intro_scheduled_cho_take_book = [gs unsigned32ForKey:@"intro_scheduled_cho_take_book"];
  intro_cho_took_book = [gs unsigned32ForKey:@"intro_cho_took_book"];
}

#pragma mark -
#pragma mark caches

- (void)_emptyPictureCaches
{
  [_picture_cache removeAllObjects];
  for (id archive_key in _dynamic_texture_cache) {
    NSMutableDictionary* archive_cache = [_dynamic_texture_cache objectForKey:archive_key];
    [archive_cache removeAllObjects];
  }
}

- (void)_resetMovieProxies
{
  NSMapEnumerator movie_enum = NSEnumerateMapTable(code_movie_map);
  uintptr_t k;
  RXMovieProxy* movie_proxy;
  while (NSNextMapEnumeratorPair(&movie_enum, (void**)&k, (void**)&movie_proxy))
    [movie_proxy deleteMovie];
  NSEndMapTableEnumeration(&movie_enum);
}

#pragma mark -
#pragma mark active card

- (RXCard*)card { return _card; }

- (void)setCard:(RXCard*)c
{
  if (c == _card)
    return;

  OSSpinLockLock(&_card_lock);

  id old = _card;
  _card = [c retain];
  [old release];

  OSSpinLockUnlock(&_card_lock);

  [self _emptyPictureCaches];
  _schedule_movie_proxy_reset = YES;
}

#pragma mark -
#pragma mark script execution

- (size_t)_executeRivenProgram:(const void*)program_buffer count:(uint16_t)optcode_count
{
  if (!controller)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"NO RIVEN SCRIPT HANDLER" userInfo:nil];

  RXStack* parent = [[_card descriptor] parent];

  // bump the execution depth
  _programExecutionDepth++;

  size_t program_off = 0;
  const uint16_t* program = (uint16_t*)program_buffer;

  uint16_t pc = 0;
  for (; pc < optcode_count; pc++) {
    if (_abortProgramExecution)
      break;

    if (*program == RX_COMMAND_BRANCH) {
      // parameters for the conditional branch opcode
      uint16_t argc = *(program + 1);
      uint16_t variable_id = *(program + 2);
      uint16_t casec = *(program + 3);

      // adjust the shorted program
      program_off += 8;
      program = (uint16_t*)BUFFER_OFFSET(program_buffer, program_off);

      // argc should always be 2 for a conditional branch
      if (argc != 2)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

      // get the variable from the game state
      NSString* name = [parent varNameAtIndex:variable_id];
      if (!name)
        name = [NSString stringWithFormat:@"%@%hu", [parent key], variable_id];
      uint16_t var_val = [[g_world gameState] unsignedShortForKey:name];

#if defined(DEBUG)
      RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@switch statement on variable %@=%hu", logPrefix, name, var_val);
#endif

      // evaluate each branch
      uint16_t casei = 0;
      uint16_t case_val;
      size_t default_case_off = 0;
      for (; casei < casec; casei++) {
        case_val = *program;

        // record the address of the default case in case we need to execute it if we don't find a matching case
        if (case_val == 0xffff)
          default_case_off = program_off;

        // matching case
        if (case_val == var_val) {
#if defined(DEBUG)
          RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@executing matching case {", logPrefix);
          [logPrefix appendString:@"    "];
#endif

          // execute the switch statement program
          program_off += [self _executeRivenProgram:(program + 2)count:*(program + 1)];

#if defined(DEBUG)
          [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
          RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
        } else
          program_off += rx_compute_riven_script_length((program + 2), *(program + 1), false); // skip over the case

        // adjust the shorted program
        program_off += 4; // account for the case value and case instruction count
        program = (uint16_t*)BUFFER_OFFSET(program_buffer, program_off);

        // bail out if we executed a matching case
        if (case_val == var_val)
          break;
      }

      // if we didn't match any case, execute the default case
      if (casei == casec && default_case_off != 0) {
#if defined(DEBUG)
        RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@no case matched variable value, executing default case {", logPrefix);
        [logPrefix appendString:@"    "];
#endif

        // execute the switch statement program
        [self _executeRivenProgram:((uint16_t*)BUFFER_OFFSET(program_buffer, default_case_off)) + 2
                             count:*(((uint16_t*)BUFFER_OFFSET(program_buffer, default_case_off)) + 1)];

#if defined(DEBUG)
        [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
        RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
      } else {
        // skip over the instructions of the remaining cases
        casei++;
        for (; casei < casec; casei++) {
          program_off += rx_compute_riven_script_length((program + 2), *(program + 1), false) + 4;
          program = (uint16_t*)BUFFER_OFFSET(program_buffer, program_off);
        }
      }
    } else {
      // execute the command
      _riven_command_dispatch_table[*program].imp(self, _riven_command_dispatch_table[*program].sel, *(program + 1), program + 2);

      // adjust the shorted program
      program_off += 4 + (*(program + 1) * sizeof(uint16_t));
      program = (uint16_t*)BUFFER_OFFSET(program_buffer, program_off);
    }
  }

  // bump down the execution depth
  release_assert(_programExecutionDepth > 0);
  _programExecutionDepth--;
  if (_programExecutionDepth == 0)
    _abortProgramExecution = NO;

  return program_off;
}

- (void)_runScreenUpdatePrograms
{
#if defined(DEBUG)
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@screen update {", logPrefix);
  [logPrefix appendString:@"    "];
#endif

  // disable screen updates while running screen update programs
  _screen_update_disable_counter++;

  NSArray* programs = [[_card scripts] objectForKey:RXScreenUpdateScriptKey];
  uint32_t programCount = [programs count];
  uint32_t programIndex = 0;
  for (; programIndex < programCount; programIndex++) {
    NSDictionary* program = [programs objectAtIndex:programIndex];
    [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes] count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
  }

  // re-enable screen updates to match the disable we did above
  if (_screen_update_disable_counter > 0)
    _screen_update_disable_counter--;

#if defined(DEBUG)
  [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
}

- (void)_updateScreen
{
  // WARNING: THIS IS NOT THREAD SAFE, BUT DOES NOT INTERFERE WITH THE RENDER THREAD

  // if screen updates are disabled, return immediatly
  if (_screen_update_disable_counter > 0) {
#if defined(DEBUG)
    if (!_doing_screen_update)
      RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@    screen update command dropped because updates are disabled", logPrefix);
#endif
    return;
  }

  // run screen update programs
  if (!_disable_screen_update_programs) {
    _doing_screen_update = YES;
    [self _runScreenUpdatePrograms];
    _doing_screen_update = NO;
  } else
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@screen update (programs disabled)", logPrefix);

  // some cards disable screen updates during screen update programs, so we
  // need to decrement the counter here to function properly; see tspit 229
  // open card
  if (_screen_update_disable_counter > 0)
    _screen_update_disable_counter--;

  // the script handler will set our front render state to our back render
  // state at the appropriate moment; when this returns, the swap has occured
  // (front == back)
  [controller update];

  if (_reset_movie_proxies) {
    [self _resetMovieProxies];
    _reset_movie_proxies = NO;
  }
}

- (void)_showMouseCursor
{
  if (_did_hide_mouse) {
    [controller showMouseCursor];
    _did_hide_mouse = NO;
  }
}

- (void)_hideMouseCursor
{
  if (!_did_hide_mouse) {
    [controller hideMouseCursor];
    _did_hide_mouse = YES;
  }
}

#pragma mark -

- (void)openCard
{
#if defined(DEBUG)
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@opening card %@ {", logPrefix, _card);
  [logPrefix appendString:@"    "];
#endif

  // retain the card while it executes programs
  RXCard* executing_card = _card;
  [executing_card retain];

  // load the card
  [_card load];

  // disable screen updates
  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);

  // clear all active hotspots and replace them with the new card's hotspots
  OSSpinLockLock(&_active_hotspots_lock);
  [_active_hotspots removeAllObjects];
  [_active_hotspots addObjectsFromArray:[_card hotspots]];
  [_active_hotspots makeObjectsPerformSelector:@selector(enable)];
  [_active_hotspots sortUsingSelector:@selector(compareByIndex:)];
  OSSpinLockUnlock(&_active_hotspots_lock);

  // reset auto-activation states
  _did_activate_plst = NO;
  _did_activate_slst = NO;

  // reset water animation
  [controller queueSpecialEffect:NULL owner:_card];

  // disable all movies on the next screen refresh (bad drawing glitches occur if this is not done, see bspit 163)
  [controller disableAllMoviesOnNextScreenUpdate];
  if (_schedule_movie_proxy_reset) {
    _schedule_movie_proxy_reset = NO;
    _reset_movie_proxies = YES;
  }

  // execute card open programs
  NSArray* programs = [[_card scripts] objectForKey:RXCardOpenScriptKey];
  uint32_t programCount = [programs count];
  uint32_t programIndex = 0;
  for (; programIndex < programCount; programIndex++) {
    NSDictionary* program = [programs objectAtIndex:programIndex];
    [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes] count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
  }

  // activate the first picture if none has been enabled already
  if ([_card pictureCount] > 0 && !_did_activate_plst) {
#if defined(DEBUG)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@automatically activating first plst record", logPrefix);
#endif
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1);
  }

  // workarounds that should execute after the open card scripts
  RXSimpleCardDescriptor* ecsd = [[_card descriptor] simpleDescriptor];

  // dome combination card - if the dome combination is 1-2-3-4-5, the opendome hotspot won't get enabled, so do it here
  if ([[_card descriptor] isCardWithRMAP:85570 stackName:@"jspit"]) {
    // check if the sliders match the dome configuration
    uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
    if (sliders_state == domecombo) {
      DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"resetsliders") ID]);
      DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"opendome") ID]);
    }
  } else if ([ecsd->stackKey isEqualToString:@"aspit"] && ecsd->cardID == 2) {
    // black card before introduction sequence - force hide the cursor to
    // prevent it from re-appearing between the moment the cross-fade
    // transition completes and the moment the first movie plays
    [self _hideMouseCursor];
  }

  // force a screen update
  _screen_update_disable_counter = 1;
  DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);

  // now run the start rendering programs
  [self startRendering];

#if defined(DEBUG)
  [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

  // we can show the mouse again (if we hid it) if the execution depth is
  // back to 0 (e.g. there are no more scripts running after this one)
  if (_programExecutionDepth == 0)
    [self _showMouseCursor];

  [executing_card release];
}

- (void)startRendering
{
#if defined(DEBUG)
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@starting rendering for card %@ {", logPrefix, _card);
  [logPrefix appendString:@"    "];
#endif

  // retain the card while it executes programs
  RXCard* executing_card = _card;
  [executing_card retain];

  // cache the card descriptor and game state for the workarounds
  RXCardDescriptor* cdesc = [_card descriptor];
  RXGameState* gs = [g_world gameState];

  // workarounds that should execute before the start rendering programs

  // execute rendering programs (index 9)
  NSArray* programs = [[_card scripts] objectForKey:RXStartRenderingScriptKey];
  uint32_t programCount = [programs count];
  uint32_t programIndex = 0;
  for (; programIndex < programCount; programIndex++) {
    NSDictionary* program = [programs objectAtIndex:programIndex];
    [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes] count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
  }

  // activate the first sound group if none has been enabled already
  if ([[_card soundGroups] count] > 0 && !_did_activate_slst) {
#if defined(DEBUG)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@automatically activating first slst record", logPrefix);
#endif
    [controller activateSoundGroup:[[_card soundGroups] objectAtIndex:0]];
    _did_activate_slst = YES;
  }

  // workarounds that should execute after the start rendering programs

  // Catherine prison card - need to schedule periodic movie events
  if ([cdesc isCardWithRMAP:14981 stackName:@"pspit"]) {
    if (!cath_prison_scdesc)
      cath_prison_scdesc = [[cdesc simpleDescriptor] retain];

    [event_timer invalidate];
    event_timer =
        [NSTimer scheduledTimerWithTimeInterval:rx_rnd_range(1, 33) target:self selector:@selector(_playCatherinePrisonMovie:) userInfo:nil repeats:NO];
  }
  // inside trap book card - schedule a deferred execution of _handleTrapBookLink on ourselves; also explicitly hide the mouse cursor for the sequence
  else if ([cdesc isCardWithRMAP:7940 stackName:@"aspit"]) {
    [self performSelector:@selector(_handleTrapBookLink) withObject:nil afterDelay:5.0];
    [controller hideMouseCursor];
  }
  // sunners cards - schedule sunners movies / events
  else if ([cdesc isCardWithRMAP:sunners_upper_stairs_rmap stackName:@"jspit"] || [cdesc isCardWithRMAP:sunners_mid_stairs_rmap stackName:@"jspit"] ||
           [cdesc isCardWithRMAP:sunners_lower_stairs_rmap stackName:@"jspit"] || [cdesc isCardWithRMAP:sunners_beach_rmap stackName:@"jspit"]) {
    if (![gs unsigned64ForKey:@"jsunners"] && !event_timer)
      event_timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(_handleSunnersIdleEvent:) userInfo:nil repeats:YES];
  }
  // office linking books - linking books change card to a dummy card, which then must change card to the destination
  else if ([cdesc isCardWithRMAP:114919 stackName:@"bspit"] || [cdesc isCardWithRMAP:70065 stackName:@"gspit"] ||
           [cdesc isCardWithRMAP:156200 stackName:@"jspit"] || [cdesc isCardWithRMAP:16648 stackName:@"pspit"] ||
           [cdesc isCardWithRMAP:138089 stackName:@"tspit"]) {
    [self performSelector:@selector(_linkToCard:)
               withObject:[RXSimpleCardDescriptor descriptorWithStackName:@"ospit" rmap:11894]
               afterDelay:kRXLinkingBookDelay];
    [controller hideMouseCursor];
  }
  // rebel age linking book
  else if ([cdesc isCardWithRMAP:166424 stackName:@"jspit"]) {
    [self performSelector:@selector(_linkToCard:)
               withObject:[RXSimpleCardDescriptor descriptorWithStackName:@"rspit" rmap:3988]
               afterDelay:kRXLinkingBookDelay];
    [controller hideMouseCursor];
  }
  // rebel age riven linking book
  else if ([cdesc isCardWithRMAP:13016 stackName:@"rspit"]) {
    [self performSelector:@selector(_linkToCard:)
               withObject:[RXSimpleCardDescriptor descriptorWithStackName:@"jspit" rmap:115828]
               afterDelay:kRXLinkingBookDelay];
    [controller hideMouseCursor];
  }
  // prison island linking book
  else if ([cdesc isCardWithRMAP:24333 stackName:@"ospit"]) {
    [self performSelector:@selector(_linkToCard:)
               withObject:[RXSimpleCardDescriptor descriptorWithStackName:@"pspit" rmap:15456]
               afterDelay:kRXLinkingBookDelay];
    [controller hideMouseCursor];
  }
  // jungle island linking book
  else if ([cdesc isCardWithRMAP:18186 stackName:@"ospit"]) {
    [self performSelector:@selector(_linkToCard:)
               withObject:[RXSimpleCardDescriptor descriptorWithStackName:@"jspit" rmap:86413]
               afterDelay:kRXLinkingBookDelay];
    [controller hideMouseCursor];
  }
  // garden island linking book
  else if ([cdesc isCardWithRMAP:23634 stackName:@"ospit"]) {
    [self performSelector:@selector(_linkToCard:)
               withObject:[RXSimpleCardDescriptor descriptorWithStackName:@"gspit" rmap:69098]
               afterDelay:kRXLinkingBookDelay];
    [controller hideMouseCursor];
  }
  // book island linking book
  else if ([cdesc isCardWithRMAP:23912 stackName:@"ospit"]) {
    [self performSelector:@selector(_linkToCard:)
               withObject:[RXSimpleCardDescriptor descriptorWithStackName:@"bspit" rmap:10439]
               afterDelay:kRXLinkingBookDelay];
    [controller hideMouseCursor];
  }
  // temple island linking book
  else if ([cdesc isCardWithRMAP:24137 stackName:@"ospit"]) {
    [self performSelector:@selector(_linkToCard:)
               withObject:[RXSimpleCardDescriptor descriptorWithStackName:@"tspit" rmap:18867]
               afterDelay:kRXLinkingBookDelay];
    [controller hideMouseCursor];
  }

#if defined(DEBUG)
  [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

  // we can show the mouse again (if we hid it) if the execution depth is
  // back to 0 (e.g. there are no more scripts running after this one)
  if (_programExecutionDepth == 0)
    [self _showMouseCursor];

  [executing_card release];
}

- (void)closeCard
{
  // we may be switching from the NULL card, so check for that and return immediately if that's the case
  if (!_card)
    return;

#if defined(DEBUG)
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@closing card %@ {", logPrefix, _card);
  [logPrefix appendString:@"    "];
#endif

  // retain the card while it executes programs
  RXCard* executing_card = _card;
  [executing_card retain];

  // execute leaving programs (index 7)
  NSArray* programs = [[_card scripts] objectForKey:RXCardCloseScriptKey];
  uint32_t programCount = [programs count];
  uint32_t programIndex = 0;
  for (; programIndex < programCount; programIndex++) {
    NSDictionary* program = [programs objectAtIndex:programIndex];
    [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes] count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
  }

#if defined(DEBUG)
  [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

  // clear all active hotspots
  OSSpinLockLock(&_active_hotspots_lock);
  [_active_hotspots removeAllObjects];
  OSSpinLockUnlock(&_active_hotspots_lock);

  // we can show the mouse again (if we hid it) if the execution depth is
  // back to 0 (e.g. there are no more scripts running after this one)
  if (_programExecutionDepth == 0)
    [self _showMouseCursor];

  [executing_card release];
}

#pragma mark -
#pragma mark hotspots

- (NSArray*)activeHotspots
{
  // WARNING: WILL BE CALLED BY THE MAIN THREAD

  OSSpinLockLock(&_active_hotspots_lock);
  NSArray* hotspots = [_active_hotspots copy];
  OSSpinLockUnlock(&_active_hotspots_lock);

  return [hotspots autorelease];
}

- (RXHotspot*)activeHotspotWithName:(NSString*)name
{
  // WARNING: WILL BE CALLED BY THE MAIN THREAD

  OSSpinLockLock(&_card_lock);
  RXHotspot* hotspot = [(RXHotspot*)NSMapGet([_card hotspotsNameMap], name) retain];
  OSSpinLockUnlock(&_card_lock);

  return [hotspot autorelease];
}

- (void)mouseInsideHotspot:(RXHotspot*)hotspot
{
  if (!hotspot)
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"hotspot CANNOT BE NIL" userInfo:nil];

#if defined(DEBUG)
#if DEBUG > 2
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouse inside %@ {", logPrefix, hotspot);
  [logPrefix appendString:@"    "];
#endif
  _disableScriptLogging = YES;
#endif

  // retain the card while it executes programs
  RXCard* executing_card = _card;
  [executing_card retain];

  // keep a weak reference to the hotspot while executing within the context of this hotspot handler
  _current_hotspot = hotspot;

  // execute mouse moved programs (index 4)
  NSArray* programs = [[hotspot scripts] objectForKey:RXMouseInsideScriptKey];
  uint32_t programCount = [programs count];
  uint32_t programIndex = 0;
  for (; programIndex < programCount; programIndex++) {
    NSDictionary* program = [programs objectAtIndex:programIndex];
    [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes] count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
  }

#if defined(DEBUG)
  _disableScriptLogging = NO;
#if DEBUG > 2
  [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
#endif

  // we can show the mouse again (if we hid it) if the execution depth is
  // back to 0 (e.g. there are no more scripts running after this one);
  // in addition, set the current hotspot back to nil
  if (_programExecutionDepth == 0) {
    _current_hotspot = nil;
    [self _showMouseCursor];
  }

  [executing_card release];
}

- (void)mouseExitedHotspot:(RXHotspot*)hotspot
{
  if (!hotspot)
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"hotspot CANNOT BE NIL" userInfo:nil];

#if defined(DEBUG)
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouse exited %@ {", logPrefix, hotspot);
  [logPrefix appendString:@"    "];
#endif

  // retain the card while it executes programs
  RXCard* executing_card = _card;
  [executing_card retain];

  // keep a weak reference to the hotspot while executing within the context of this hotspot handler
  _current_hotspot = hotspot;

  // execute mouse leave programs (index 5)
  NSArray* programs = [[hotspot scripts] objectForKey:RXMouseExitedScriptKey];
  uint32_t programCount = [programs count];
  uint32_t programIndex = 0;
  for (; programIndex < programCount; programIndex++) {
    NSDictionary* program = [programs objectAtIndex:programIndex];
    [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes] count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
  }

#if defined(DEBUG)
  [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

  // we can show the mouse again (if we hid it) if the execution depth is
  // back to 0 (e.g. there are no more scripts running after this one);
  // in addition, set the current hotspot back to nil
  if (_programExecutionDepth == 0) {
    _current_hotspot = nil;
    [self _showMouseCursor];
  }

  [executing_card release];
}

- (void)mouseDownInHotspot:(RXHotspot*)hotspot
{
  if (!hotspot)
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"hotspot CANNOT BE NIL" userInfo:nil];

#if defined(DEBUG)
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouse down in %@ {", logPrefix, hotspot);
  [logPrefix appendString:@"    "];
#endif

  // retain the card while it executes programs
  RXCard* executing_card = _card;
  [executing_card retain];

  // keep a weak reference to the hotspot while executing within the context of this hotspot handler
  _current_hotspot = hotspot;

  // execute mouse down programs (index 0)
  NSArray* programs = [[hotspot scripts] objectForKey:RXMouseDownScriptKey];
  uint32_t programCount = [programs count];
  uint32_t programIndex = 0;
  for (; programIndex < programCount; programIndex++) {
    NSDictionary* program = [programs objectAtIndex:programIndex];
    [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes] count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
  }

#if defined(DEBUG)
  [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

  // we can show the mouse again (if we hid it) if the execution depth is
  // back to 0 (e.g. there are no more scripts running after this one);
  // in addition, set the current hotspot back to nil
  if (_programExecutionDepth == 0) {
    _current_hotspot = nil;
    [self _showMouseCursor];
  }

  [executing_card release];

  // we need to enable hotspot handling at the end of mouse down messages
  [controller enableHotspotHandling];
}

- (void)mouseUpInHotspot:(RXHotspot*)hotspot
{
  if (!hotspot)
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"hotspot CANNOT BE NIL" userInfo:nil];

#if defined(DEBUG)
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouse up in %@ {", logPrefix, hotspot);
  [logPrefix appendString:@"    "];
#endif

  // retain the card while it executes programs
  RXCard* executing_card = _card;
  [executing_card retain];

  // keep a weak reference to the hotspot while executing within the context of this hotspot handler
  _current_hotspot = hotspot;

  // execute mouse up programs (index 2)
  NSArray* programs = [[hotspot scripts] objectForKey:RXMouseUpScriptKey];
  uint32_t programCount = [programs count];
  uint32_t programIndex = 0;
  for (; programIndex < programCount; programIndex++) {
    NSDictionary* program = [programs objectAtIndex:programIndex];
    [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes] count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
  }

#if defined(DEBUG)
  [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

  // we can show the mouse again (if we hid it) if the execution depth is
  // back to 0 (e.g. there are no more scripts running after this one);
  // in addition, set the current hotspot back to nil
  if (_programExecutionDepth == 0) {
    _current_hotspot = nil;
    [self _showMouseCursor];
  }

  [executing_card release];

  // we need to enable hotspot handling at the end of mouse up messages
  [controller enableHotspotHandling];
}

#pragma mark -
#pragma mark movie playback

- (void)skipBlockingMovie
{
  // WARNING: WILL RUN ON MAIN THREAD
  if (_blocking_movie)
    [(RXMovie*)_blocking_movie gotoEnd];

  if (!intro_atrus_gave_books && intro_scheduled_atrus_give_books) {
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(_enableAtrusJournal) object:nil];
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(_enableTrapBook) object:nil];
    [self performSelector:@selector(_enableAtrusJournal)];
    [self performSelector:@selector(_enableTrapBook)];
  }

  if (!intro_cho_took_book && intro_scheduled_cho_take_book) {
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(_disableTrapBook) object:nil];
    [self performSelector:@selector(_disableTrapBook)];
  }
}

- (void)_handleBlockingMovieFinishedPlaying:(NSNotification*)notification
{
  // WARNING: WILL RUN ON MAIN THREAD
  if (_blocking_movie && [_blocking_movie proxiedMovie] == [notification object]) {
    [_blocking_movie release];
    _blocking_movie = nil;
    OSMemoryBarrier();
  }
}

- (void)_playMovie:(RXMovie*)movie
{
  // WARNING: MUST RUN ON MAIN THREAD
  debug_assert([movie isKindOfClass:[RXMovieProxy class]]);

  // if the movie is scheduled for reset, do the reset now
  if ([_movies_to_reset containsObject:movie]) {
    [movie reset];
    [_movies_to_reset removeObject:movie];
  }

  // start playing the movie
  [movie play];
}

- (void)_stopMovie:(RXMovie*)movie
{
  // WARNING: MUST RUN ON MAIN THREAD
  [movie stop];
}

- (void)_resetMovie:(RXMovie*)movie
{
  // WARNING: MUST RUN ON MAIN THREAD

  // the movie could be enabled (the bspit 279 book shows this), in which
  // case we need to defer the reset until the movie is played or enabled
  if ([controller isMovieEnabled:movie]) {
#if defined(DEBUG)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@deferring reset of movie %@ because it is enabled", logPrefix, movie);
#endif
    [_movies_to_reset addObject:movie];
  } else
    [movie reset];
}

- (void)_muteMovie:(RXMovie*)movie
{
  // WARNING: MUST RUN ON MAIN THREAD
  [movie setVolume:0.0f];
}

- (void)_unmuteMovie:(RXMovie*)movie
{
  // WARNING: MUST RUN ON MAIN THREAD
  debug_assert([movie isKindOfClass:[RXMovieProxy class]]);
  [(RXMovieProxy*)movie restoreMovieVolume];
}

- (void)_disableLoopingOnMovie:(RXMovie*)movie
{
  // WARNING: MUST RUN ON MAIN THREAD
  [movie setLooping:NO];
}

- (void)_checkScheduledMovieCommandWithCode:(uint16_t)code movie:(RXMovie*)movie
{
  if (_scheduled_movie_command.code != code) {
    memset(&_scheduled_movie_command, 0, sizeof(rx_scheduled_movie_command_t));
    return;
  }

  NSTimeInterval movie_position;
  QTGetTimeInterval([movie _noLockCurrentTime], &movie_position);
  if (movie_position > _scheduled_movie_command.time) {
#if defined(DEBUG)
    if (!_disableScriptLogging) {
      RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@executing scheduled movie command {", logPrefix);
      [logPrefix appendString:@"    "];
    }
#endif
    DISPATCH_COMMAND2(_scheduled_movie_command.command[0], _scheduled_movie_command.command[1], _scheduled_movie_command.command[2]);
#if defined(DEBUG)
    if (!_disableScriptLogging) {
      [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
      RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
    }
#endif

    memset(&_scheduled_movie_command, 0, sizeof(rx_scheduled_movie_command_t));
  }
}

#pragma mark -
#pragma mark dynamic pictures

- (void)_drawPictureWithID:(uint16_t)tbmp_id archive:(MHKArchive*)archive displayRect:(NSRect)display_rect samplingRect:(NSRect)sampling_rect
{
  // get the resource descriptor for the tBMP resource
  NSError* error;
  NSDictionary* picture_descriptor = [archive bitmapDescriptorWithID:tbmp_id error:&error];
  if (!picture_descriptor)
    @throw [NSException exceptionWithName:@"RXPictureLoadException"
                                   reason:@"Could not get a picture resource's picture descriptor."
                                 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
  GLsizei picture_width = [[picture_descriptor objectForKey:@"Width"] intValue];
  GLsizei picture_height = [[picture_descriptor objectForKey:@"Height"] intValue];

  // if the sampling rect is empty, use the picture's full resolution
  if (NSIsEmptyRect(sampling_rect))
    sampling_rect.size = NSMakeSize(picture_width, picture_height);

  // clamp the size of the sampling rect to the picture's resolution
  if (sampling_rect.size.width > picture_width)
    sampling_rect.size.width = picture_width;
  if (sampling_rect.size.height > picture_height) {
    sampling_rect.origin.y += sampling_rect.size.height - picture_height;
    sampling_rect.size.height = picture_height;
  }

  // make sure the display rect is not larger than the picture -- pictures
  // are clipped to the top-left corner of their display rects, they're never scaled
  if (display_rect.size.width > sampling_rect.size.width)
    display_rect.size.width = sampling_rect.size.width;
  if (display_rect.size.height > sampling_rect.size.height) {
    display_rect.origin.y += display_rect.size.height - sampling_rect.size.height;
    display_rect.size.height = sampling_rect.size.height;
  }

  // check if we have the texture in the dynamic texture cache
  NSString* archive_key = [[[[archive url] path] lastPathComponent] stringByDeletingPathExtension];
  NSMutableDictionary* archive_tex_cache = [_dynamic_texture_cache objectForKey:archive_key];
  if (!archive_tex_cache) {
    archive_tex_cache = [NSMutableDictionary new];
    [_dynamic_texture_cache setObject:archive_tex_cache forKey:archive_key];
    [archive_tex_cache release];
  }

  NSNumber* dynamic_texture_key = [NSNumber numberWithUnsignedInt:(unsigned int)tbmp_id << 2];
  RXTexture* picture_texture = [archive_tex_cache objectForKey:dynamic_texture_key];
  if (!picture_texture) {
    picture_texture = [[RXTextureBroker sharedTextureBroker] newTextureWithWidth:picture_width height:picture_height];
    [picture_texture updateWithBitmap:tbmp_id archive:archive];

    // map the tBMP ID to the texture object
    [archive_tex_cache setObject:picture_texture forKey:dynamic_texture_key];
    [picture_texture release];
  }

  // create a RXDynamicPicture object and queue it for rendering
  RXDynamicPicture* picture = [[RXDynamicPicture alloc] initWithTexture:picture_texture samplingRect:sampling_rect renderRect:display_rect owner:self];
  [controller queuePicture:picture];
  [picture release];

  // swap the render state; this always marks the back render state as modified
  [self _updateScreen];
}

- (void)_drawPictureWithID:(uint16_t)tbmp_id stack:(RXStack*)stack displayRect:(NSRect)display_rect samplingRect:(NSRect)sampling_rect
{
  MHKArchive* archive = [[stack fileWithResourceType:@"tBMP" ID:tbmp_id] archive];
  [self _drawPictureWithID:tbmp_id archive:archive displayRect:display_rect samplingRect:sampling_rect];
}

#pragma mark -
#pragma mark sound playback

- (void)_playDataSoundWithID:(uint16_t)twav_id gain:(float)gain duration:(double*)duration_ptr
{
  RXDataSound* sound = [RXDataSound new];
  sound->parent = [[_card descriptor] parent];
  sound->twav_id = twav_id;
  sound->gain = gain;
  sound->pan = 0.5f;

  [controller playDataSound:sound];

  if (duration_ptr)
    *duration_ptr = [sound duration];
  [sound release];
}

#pragma mark -
#pragma mark endgame

- (void)_endgameWithCode:(uint16_t)movie_code delay:(double)delay
{
  // disable the inventory
  [[g_world gameState] setUnsigned32:0 forKey:@"ainventory"];

  // stop all ambient sound
  DISPATCH_COMMAND1(RX_COMMAND_CLEAR_SLST, 0);

  // begin playback of the endgame movie
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE, movie_code);
  NSTimeInterval movie_start_ts = CFAbsoluteTimeGetCurrent();

  // get the endgame movie object
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)(uintptr_t)movie_code);

  // get its duration and video duration
  NSTimeInterval duration;
  QTGetTimeInterval([movie duration], &duration);

  NSTimeInterval video_duration;
  QTGetTimeInterval([movie videoDuration], &video_duration);

  // sleep for the duration of the video track (the ending movies also include the credit music) plus the specified delay
  usleep((video_duration - (CFAbsoluteTimeGetCurrent() - movie_start_ts) + delay) * 1E6);

// start the credits
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@beginning credits", logPrefix);
#endif

  [controller beginEndCredits];
}

- (void)_endgameWithMLST:(uint16_t)movie_mlst delay:(double)delay
{
  uint16_t movie_code = [_card movieCodes][movie_mlst - 1];
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_MLST, movie_mlst);
  [self _endgameWithCode:movie_code delay:delay];
}

#pragma mark -
#pragma mark script opcodes

- (void)_invalid_opcode:(const uint16_t)argc arguments:(const uint16_t*)argv __attribute__((noreturn))
{
  @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                 reason:[NSString stringWithFormat:@"INVALID RIVEN SCRIPT OPCODE EXECUTED: %d", argv[-2]]
                               userInfo:nil];
}

- (void)_opcode_unimplemented:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  uint16_t argi = 0;
  NSString* fmt_str = [NSString stringWithFormat:@"WARNING: opcode %hu not implemented, arguments: {", *(argv - 2)];
  if (argc > 1) {
    for (; argi < argc - 1; argi++)
      fmt_str = [fmt_str stringByAppendingFormat:@"%hu, ", argv[argi]];
  }

  if (argc > 0)
    fmt_str = [fmt_str stringByAppendingFormat:@"%hu", argv[argi]];

  fmt_str = [fmt_str stringByAppendingString:@"}"];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@%@", logPrefix, fmt_str);
}

- (void)_opcode_noop:(const uint16_t)argc arguments:(const uint16_t*)argv {}

// 1
- (void)_opcode_drawDynamicPicture:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 9)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  NSRect display_rect = RXMakeCompositeDisplayRect(argv[1], argv[2], argv[3], argv[4]);
  NSRect sampling_rect = NSMakeRect(argv[5], argv[6], argv[7] - argv[5], argv[8] - argv[6]);

#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@drawing dynamic picture ID %hu in rect {{%f, %f}, {%f, %f}}", logPrefix, argv[0], display_rect.origin.x,
          display_rect.origin.y, display_rect.size.width, display_rect.size.height);
#endif

  [self _drawPictureWithID:argv[0] stack:[_card parent] displayRect:display_rect samplingRect:sampling_rect];
}

// 2
- (void)_opcode_goToCard:(const uint16_t)argc arguments:(const uint16_t*)argv
{
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@going to card ID %hu", logPrefix, argv[0]);
#endif

  RXStack* parent = [[_card descriptor] parent];
  [controller setActiveCardWithStack:[parent key] ID:argv[0] waitUntilDone:YES];
}

// 3
- (void)_opcode_activateSynthesizedSLST:(const uint16_t)argc arguments:(const uint16_t*)argv
{
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling a synthesized slst record", logPrefix);
#endif

  RXSoundGroup* oldSoundGroup = _synthesizedSoundGroup;

  // argv + 1 is suitable for _createSoundGroupWithSLSTRecord
  uint16_t soundCount = argv[0];
  _synthesizedSoundGroup = [_card newSoundGroupWithSLSTRecord:(argv + 1)soundCount:soundCount swapBytes:NO];

  [controller activateSoundGroup:_synthesizedSoundGroup];
  _did_activate_slst = YES;

  [oldSoundGroup release];
}

// 4
- (void)_opcode_playDataSound:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 3)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@playing local sound resource id=%hu, volume=%hu, blocking=%hu", logPrefix, argv[0], argv[1], argv[2]);
#endif

  double duration = 0.0;
  [self _playDataSoundWithID:argv[0] gain:(float)argv[1] / kRXSoundGainDivisor duration:&duration];
  CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();

  // argv[2] is a "wait for sound" boolean
  if (argv[2]) {
    // hide the mouse cursor
    [self _hideMouseCursor];

    // sleep for the duration minus the time that has elapsed since we started the sound
    usleep((duration - (CFAbsoluteTimeGetCurrent() - now)) * 1E6);
  }
}

// 5
- (void)_opcode_activateSynthesizedMLST:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 10)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  // there's always going to be something before argv, so doing the -1 offset here is fine
  struct rx_mlst_record* mlst_r = (struct rx_mlst_record*)(argv - 1);

#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating synthesized MLST [movie_id=%hu, code=%hu]", logPrefix, mlst_r->movie_id, mlst_r->code);
#endif

  // have the card load the movie
  RXMovie* movie = [_card loadMovieWithMLSTRecord:mlst_r];

  // update the code to movie map
  uintptr_t k = mlst_r->code;
  NSMapInsert(code_movie_map, (const void*)k, movie);

  // schedule the movie for reset
  [_movies_to_reset addObject:movie];

  // should re-apply the MLST settings to the movie here, but because of the way RX is setup, we don't need to do that
  // in particular, _resetMovie will reset the movie back to the beginning and invalidate any decoded frame it may have
}

// 7
- (void)_opcode_setVariable:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 2)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  RXStack* parent = [[_card descriptor] parent];
  NSString* name = [parent varNameAtIndex:argv[0]];
  if (!name)
    name = [NSString stringWithFormat:@"%@%hu", [parent key], argv[0]];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@setting variable %@ to %hu", logPrefix, name, argv[1]);
#endif

  [[g_world gameState] setUnsignedShort:argv[1] forKey:name];
}

// 9
- (void)_opcode_enableHotspot:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling hotspot %hu", logPrefix, argv[0]);
#endif

  uintptr_t k = argv[0];
  RXHotspot* hotspot = (RXHotspot*)NSMapGet([_card hotspotsIDMap], (void*)k);
  release_assert(hotspot);

  if (!hotspot->enabled) {
    hotspot->enabled = YES;

    OSSpinLockLock(&_active_hotspots_lock);
    [_active_hotspots addObject:hotspot];
    [_active_hotspots sortUsingSelector:@selector(compareByIndex:)];
    OSSpinLockUnlock(&_active_hotspots_lock);

    // instruct the script handler to update the hotspot state
    [controller updateHotspotState];
  }
}

// 10
- (void)_opcode_disableHotspot:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling hotspot %hu", logPrefix, argv[0]);
#endif

  uintptr_t k = argv[0];
  RXHotspot* hotspot = (RXHotspot*)NSMapGet([_card hotspotsIDMap], (void*)k);
  release_assert(hotspot);

  if (hotspot->enabled) {
    hotspot->enabled = NO;

    OSSpinLockLock(&_active_hotspots_lock);
    [_active_hotspots removeObject:hotspot];
    [_active_hotspots sortUsingSelector:@selector(compareByIndex:)];
    OSSpinLockUnlock(&_active_hotspots_lock);

    // instruct the script handler to update the hotspot state
    [controller updateHotspotState];
  }
}

// 12
- (void)_opcode_clearSounds:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  uint16_t options = argv[0];

#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@clearing sounds with options %hu", logPrefix, options);
#endif

  if ((options & 2) || !options) {
    // synthesize and activate an empty sound group
    RXSoundGroup* sgroup = [RXSoundGroup new];
    sgroup->gain = 1.0f;
    sgroup->loop = NO;
    sgroup->fadeOutRemovedSounds = NO;
    sgroup->fadeInNewSounds = NO;

    [controller activateSoundGroup:sgroup];
    [sgroup release];
  }

  if ((options & 1) || !options) {
    // foreground sounds
  }
}

// 13
- (void)_opcode_setCursor:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@setting cursor to %hu", logPrefix, argv[0]);
#endif

  [controller setMouseCursor:argv[0]];
}

// 14
- (void)_opcode_pause:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@pausing for %d msec", logPrefix, argv[0]);
#endif

  // in case the pause delay is 0, just return immediatly
  if (argv[0] == 0)
    return;

  // hide the mouse cursor
  [self _hideMouseCursor];

  // sleep for the specified amount of ms
  usleep(argv[0] * 1000);
}

// 17
- (void)_opcode_callExternal:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  uint16_t external_id = argv[0];
  uint16_t external_argc = argv[1];

  NSString* external_name = [[[[_card descriptor] parent] externalNameAtIndex:external_id] lowercaseString];
  if (!external_name)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID EXTERNAL COMMAND ID" userInfo:nil];

#if defined(DEBUG)
  NSString* fmt = [NSString stringWithFormat:@"calling external %@(", external_name];

  uint16_t argi = 0;
  if (external_argc > 1) {
    for (; argi < external_argc - 1; argi++)
      fmt = [fmt stringByAppendingFormat:@"%hu, ", argv[2 + argi]];
  }

  if (external_argc > 0)
    fmt = [fmt stringByAppendingFormat:@"%hu", argv[2 + argi]];

  fmt = [fmt stringByAppendingString:@") {"];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@%@", logPrefix, fmt);

  // augment script log indentation for the external command
  [logPrefix appendString:@"    "];
#endif

  // dispatch the call to the external command
  rx_command_dispatch_entry_t* command_dispatch = (rx_command_dispatch_entry_t*)NSMapGet(_riven_external_command_dispatch_map, external_name);
  if (!command_dispatch) {
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@    WARNING: external command '%@' is not implemented!", logPrefix, external_name);
#if defined(DEBUG)
    [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
    return;
  }

  command_dispatch->imp(self, command_dispatch->sel, external_argc, argv + 2);

#if defined(DEBUG)
  [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
}

// 18
- (void)_opcode_scheduleTransition:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc != 1 && argc != 5)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  uint16_t code = argv[0];

  NSRect rect;
  if (argc > 1)
    rect = RXMakeCompositeDisplayRect(argv[1], argv[2], argv[3], argv[4]);
  else
    rect = NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height);

  RXTransition* transition = [[RXTransition alloc] initWithCode:code region:rect];

#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelMessage, @"%@scheduling transition %@", logPrefix, transition);
#endif

  // queue the transition
  [controller queueTransition:transition];

  // transition is now owned by the transition queue
  [transition release];
}

// 19
- (void)_opcode_reloadCard:(const uint16_t)argc arguments:(const uint16_t*)argv
{
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@reloading card", logPrefix);
#endif

  // this command reloads whatever is the current card
  RXSimpleCardDescriptor* current_card = [[g_world gameState] currentCard];
  [controller setActiveCardWithStack:current_card->stackKey ID:current_card->cardID waitUntilDone:YES];
}

// 20
- (void)_opcode_disableScreenUpdates:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  _screen_update_disable_counter++;
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling screen updates (%d)", logPrefix, _screen_update_disable_counter);
#endif
}

// 21
- (void)_opcode_enableScreenUpdates:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (_screen_update_disable_counter > 0)
    _screen_update_disable_counter--;

#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling screen updates (%d)", logPrefix, _screen_update_disable_counter);
#endif

  // this command also triggers a screen update (which may be dropped if the counter is still not 0)
  [self _updateScreen];
}

// 24
- (void)_opcode_incrementVariable:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 2)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  RXStack* parent = [[_card descriptor] parent];
  NSString* name = [parent varNameAtIndex:argv[0]];
  if (!name)
    name = [NSString stringWithFormat:@"%@%hu", [parent key], argv[0]];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@incrementing variable %@ by %hu", logPrefix, name, argv[1]);
#endif

  uint16_t v = [[g_world gameState] unsignedShortForKey:name];
  [[g_world gameState] setUnsignedShort:(v + argv[1])forKey:name];
}

// 25
- (void)_opcode_decrementVariable:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 2)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  RXStack* parent = [[_card descriptor] parent];
  NSString* name = [parent varNameAtIndex:argv[0]];
  if (!name)
    name = [NSString stringWithFormat:@"%@%hu", [parent key], argv[0]];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@decrementing variable %@ by %hu", logPrefix, name, argv[1]);
#endif

  uint16_t v = [[g_world gameState] unsignedShortForKey:name];
  [[g_world gameState] setUnsignedShort:(v - argv[1])forKey:name];
}

// 26
- (void)_opcode_closeAllMovies:(const uint16_t)argc arguments:(const uint16_t*)argv
{
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@closing all movies", logPrefix);
#endif
}

// 27
- (void)_opcode_goToStack:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 3)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  // get the stack for the given stack key
  NSString* k = [[[_card descriptor] parent] stackNameAtIndex:argv[0]];
  RXStack* stack = [g_world loadStackWithKey:k];
  if (!stack) {
    RXLog(kRXLoggingScript, kRXLoggingLevelError, @"aborting script execution: goToStack opcode failed to load stack '%@'", k);
    _abortProgramExecution = YES;
    return;
  }

  uint32_t card_rmap = (argv[1] << 16) | argv[2];
  uint16_t card_id = [stack cardIDFromRMAPCode:card_rmap];

#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@going to stack %@ on card ID %hu", logPrefix, k, card_id);
#endif

  [controller setActiveCardWithStack:k ID:card_id waitUntilDone:YES];
}

// 28
- (void)_opcode_disableMovie:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling movie with code %hu", logPrefix, argv[0]);
#endif

  // get the movie object
  uintptr_t k = argv[0];
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)k);

  // it is legal to disable a code that has no movie associated with it
  if (!movie)
    return;

  // disable the movie
  [controller disableMovie:movie];
}

// 29
- (void)_opcode_disableAllMovies:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling all movies", logPrefix);
#endif

  // disable all movies
  [controller disableAllMovies];
}

// 31
- (void)_opcode_enableMovie:(const uint16_t)argc arguments:(const uint16_t*)argv
{
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling movie with code %hu", logPrefix, argv[0]);
#endif

  // get the movie object
  uintptr_t k = argv[0];
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)k);

  // it is legal to enable a code that has no movie associated with it
  if (!movie)
    return;

  // if the movie is scheduled for reset, do the reset now
  if ([_movies_to_reset containsObject:movie]) {
    [self performSelectorOnMainThread:@selector(_resetMovie:) withObject:movie waitUntilDone:YES];
    [_movies_to_reset removeObject:movie];
  }

  // enable the movie
  [controller enableMovie:movie];
}

// 32
- (void)_opcode_startMovieAndWaitUntilDone:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@starting movie with code %hu and waiting until done", logPrefix, argv[0]);
#endif

  // get the movie object
  uintptr_t k = argv[0];
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)k);

  // it is legal to play a code that has no movie associated with it; it's a no-op
  if (!movie)
    return;

  // hide the mouse cursor
  [self _hideMouseCursor];

  // start the movie
  _blocking_movie = (RXMovieProxy*)[movie retain];
  [self performSelectorOnMainThread:@selector(_disableLoopingOnMovie:) withObject:movie waitUntilDone:NO];
  [self performSelectorOnMainThread:@selector(_playMovie:) withObject:movie waitUntilDone:YES];

  // enable the movie
  [controller enableMovie:movie];

  // wait until the movie is done playing
  while (1) {
    [self _checkScheduledMovieCommandWithCode:argv[0] movie:movie];

    if (!_blocking_movie)
      break;

    usleep(kRunloopPeriodMicroseconds);
  }

  // check for the scheduled movie command one more time
  [self _checkScheduledMovieCommandWithCode:argv[0] movie:movie];

  // wipe any scheduled movie command
  memset(&_scheduled_movie_command, 0, sizeof(rx_scheduled_movie_command_t));
}

// 33
- (void)_opcode_startMovie:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@starting movie with code %hu", logPrefix, argv[0]);
#endif

  // get the movie object
  uintptr_t k = argv[0];
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)k);

  // it is legal to play a code that has no movie associated with it; it's a no-op
  if (!movie)
    return;

  // start the movie and block until done
  [self performSelectorOnMainThread:@selector(_playMovie:) withObject:movie waitUntilDone:YES];

  // enable the movie
  [controller enableMovie:movie];
}

// 34
- (void)_opcode_stopMovie:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@stopping movie with code %hu", logPrefix, argv[0]);
#endif

  // get the movie object
  uintptr_t k = argv[0];
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)k);

  // it is legal to stop a code that has no movie associated with it; it's a no-op
  if (!movie)
    return;

  // stop the movie and block until done
  [self performSelectorOnMainThread:@selector(_stopMovie:) withObject:movie waitUntilDone:YES];
}

// 37
- (void)_opcode_fadeAmbientSounds:(const uint16_t)argc arguments:(const uint16_t*)argv
{
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@fading out ambient sounds", logPrefix);
#endif

  // synthesize and activate an empty sound group
  RXSoundGroup* sgroup = [RXSoundGroup new];
  sgroup->gain = 1.0f;
  sgroup->loop = NO;
  sgroup->fadeOutRemovedSounds = YES;
  sgroup->fadeInNewSounds = NO;

  [controller activateSoundGroup:sgroup];
  [sgroup release];
}

// 38
- (void)_opcode_scheduleMovieCommand:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 5)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  uint32_t command_time = (argv[1] << 16) | argv[2];
  uint16_t movie_code = argv[0];
  uint16_t command = argv[3];
  uint16_t command_arg = argv[4];

#if defined(DEBUG)
  if (!_disableScriptLogging) {
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@scheduling command %d with argument %d at %u ms tied to movie code %hu", logPrefix, command, command_arg,
          command_time, movie_code);
  }
#endif

  // schedule the command
  if (command_time > 0) {
    _scheduled_movie_command.code = movie_code;
    _scheduled_movie_command.time = command_time / 1000.0;
    _scheduled_movie_command.command[0] = command;
    _scheduled_movie_command.command[1] = command_arg;
    _scheduled_movie_command.command[2] = (argc > 5) ? argv[5] : 0;
  } else {
    memset(&_scheduled_movie_command, 0, sizeof(rx_scheduled_movie_command_t));
    DISPATCH_COMMAND1(command, command_arg);
  }
}

// 39
- (void)_opcode_activatePLST:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  // get the picture record from the card
  unsigned int index = argv[0] - 1;
  struct rx_plst_record* picture_record = [_card pictureRecords] + index;

#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating plst record at index %hu [tBMP=%hu]", logPrefix, argv[0], picture_record->bitmap_id);
#endif

  // lookup the picture in the current card picture cache
  NSNumber* picture_key = [NSNumber numberWithUnsignedInt:index << 2];
  RXPicture* picture = [_picture_cache objectForKey:picture_key];
  if (!picture) {
    // if VRAM gets below 32 MiB, empty the picture cache
    if ([g_worldView currentFreeVRAM] < 32 * 1024 * 1024)
      [self _emptyPictureCaches];

    // get a texture from the texture broker
    MHKArchive* archive = [[[_card parent] fileWithResourceType:@"tBMP" ID:picture_record->bitmap_id] archive];
    release_assert(archive);

    NSError* error;
    NSDictionary* picture_descriptor = [archive bitmapDescriptorWithID:picture_record->bitmap_id error:&error];
    if (!picture_descriptor)
      @throw [NSException exceptionWithName:@"RXPictureLoadException"
                                     reason:@"Could not get a picture resource's picture descriptor."
                                   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];

    rx_size_t picture_size = RXSizeMake([[picture_descriptor objectForKey:@"Width"] intValue], [[picture_descriptor objectForKey:@"Height"] intValue]);
    RXTexture* picture_texture = [[RXTextureBroker sharedTextureBroker] newTextureWithSize:picture_size];

    // update the texture with the content of the picture
    [picture_texture updateWithBitmap:picture_record->bitmap_id archive:archive];

    // create suitable sampling and display rects
    NSRect display_rect = RXMakeCompositeDisplayRectFromCoreRect(picture_record->rect);
    NSRect sampling_rect = NSMakeRect(0.0f, 0.0f, display_rect.size.width, display_rect.size.height);

    // create a dynamic picture around the texture
    picture = [[RXDynamicPicture alloc] initWithTexture:picture_texture samplingRect:sampling_rect renderRect:display_rect owner:self];
    [picture_texture release];

    // store the picture in the cache
    [_picture_cache setObject:picture forKey:picture_key];
    [picture release];
  }

  // queue the picture for display
  [controller queuePicture:picture];

  // opcode 39 triggers a screen update
  [self _updateScreen];

  // indicate that an PLST record has been activated (to manage the automatic activation of PLST record 1 if none has been)
  _did_activate_plst = YES;
}

// 40
- (void)_opcode_activateSLST:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating slst record at index %hu", logPrefix, argv[0]);
#endif

  // activate the sound group
  [controller activateSoundGroup:[[_card soundGroups] objectAtIndex:argv[0] - 1]];

  // indicate that an SLST record has been activated (to manage the automatic activation of SLST record 1 if none has been)
  _did_activate_slst = YES;
}

// 41
- (void)_opcode_activateMLSTAndStartMovie:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  uint16_t code = [_card movieCodes][argv[0] - 1];

#if defined(DEBUG)
  if (!_disableScriptLogging) {
    RXLog(kRXLoggingScript, kRXLoggingLevelMessage, @"%@activating mlst record %hu [code=%hu] and starting movie {", logPrefix, argv[0], code);
    [logPrefix appendString:@"    "];
  }
#endif

  DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, argv[0], 0);
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE, code);

#if defined(DEBUG)
  if (!_disableScriptLogging) {
    [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
  }
#endif
}

// 43
- (void)_opcode_activateBLST:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating blst record at index %hu", logPrefix, argv[0]);
#endif

  struct rx_blst_record* record = [_card hotspotControlRecords] + (argv[0] - 1);
  uintptr_t k = record->hotspot_id;
  RXHotspot* hotspot = (RXHotspot*)NSMapGet([_card hotspotsIDMap], (void*)k);
  release_assert(hotspot);

  OSSpinLockLock(&_active_hotspots_lock);
  if (record->enabled == 1 && !hotspot->enabled)
    [_active_hotspots addObject:hotspot];
  else if (record->enabled == 0 && hotspot->enabled)
    [_active_hotspots removeObject:hotspot];
  OSSpinLockUnlock(&_active_hotspots_lock);

  hotspot->enabled = record->enabled;

  OSSpinLockLock(&_active_hotspots_lock);
  [_active_hotspots sortUsingSelector:@selector(compareByIndex:)];
  OSSpinLockUnlock(&_active_hotspots_lock);

  // instruct the script handler to update the hotspot state
  [controller updateHotspotState];
}

// 44
- (void)_opcode_activateFLST:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating flst record at index %hu", logPrefix, argv[0]);
#endif

  [controller queueSpecialEffect:[_card sfxes] + (argv[0] - 1)owner:_card];
}

// 46
- (void)_opcode_activateMLST:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
  uintptr_t k = [_card movieCodes][argv[0] - 1];

#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating mlst record %hu [code=%lu]", logPrefix, argv[0], k);
#endif

  // update the code to movie map
  RXMovie* movie = [[_card movies] objectAtIndex:argv[0] - 1];
  NSMapInsert(code_movie_map, (const void*)k, movie);

  // schedule the movie for reset
  [_movies_to_reset addObject:movie];

  // should re-apply the MLST settings to the movie here, but because of the way RX is setup, we don't need to do that;
  // specifically, movie reset will put the movie back to its beginning and invalidate any decoded frame it may have
}

// 47
- (void)_opcode_activateSLSTWithVolume:(const uint16_t)argc arguments:(const uint16_t*)argv
{
  if (argc < 2)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating slst record at index %hu and overriding volunme to %hu", logPrefix, argv[0], argv[1]);
#endif

  // get the sound group
  RXSoundGroup* sg = [[_card soundGroups] objectAtIndex:argv[0] - 1];

  // temporarily change its gain
  uint16_t integer_gain = argv[1];
  float gain = (float)integer_gain / kRXSoundGainDivisor;
  float original_gain = sg->gain;
  sg->gain = gain;

  // activate the sound group
  [controller activateSoundGroup:sg];

  // indicate that an SLST record has been activated (to manage the automatic activation of SLST record 1 if none has been)
  _did_activate_slst = YES;

  // restore its original gain
  sg->gain = original_gain;
}

#pragma mark -
#pragma mark main menu

DEFINE_COMMAND(xarestoregame)
{ [[RXApplicationDelegate sharedApplicationDelegate] performSelectorOnMainThread:@selector(openDocument:) withObject:self waitUntilDone:NO]; }

DEFINE_COMMAND(xasetupcomplete)
{
  // schedule a fade transition
  DISPATCH_COMMAND1(RX_COMMAND_SCHEDULE_TRANSITION, 16);

  // clear the ambient sound
  DISPATCH_COMMAND1(RX_COMMAND_CLEAR_SLST, 0);

  // go to card 1
  DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, 1);
}

DEFINE_COMMAND(xastartupbtnhide)
{
  // not implementing this for Riven X
}

#pragma mark -
#pragma mark inventory

DEFINE_COMMAND(xthideinventory)
{
  // nothing to do in Riven X for this really
}

#pragma mark -
#pragma mark shared journal support

- (void)_returnFromJournal
{
  // schedule a cross-fade transition to the return card
  RXTransition* transition =
      [[RXTransition alloc] initWithType:RXTransitionDissolve direction:0 region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
  [controller queueTransition:transition];
  [transition release];

  // change the active card to the saved return card
  RXSimpleCardDescriptor* returnCard = [[g_world gameState] returnCard];
  [controller setActiveCardWithStack:returnCard->stackKey ID:returnCard->cardID waitUntilDone:YES];

  // reset the return card
  [[g_world gameState] setReturnCard:nil];

  // enable the inventory
  [[g_world gameState] setUnsigned32:1 forKey:@"ainventory"];
}

- (void)_flipPageWithTransitionDirection:(RXTransitionDirection)direction
{
  uint16_t page_sound = [_card dataSoundIDWithName:rx_rnd_bool() ? @"aPage1" : @"aPage2"];
  [self _playDataSoundWithID:page_sound gain:0.2f duration:NULL];

  RXTransition* transition =
      [[RXTransition alloc] initWithType:RXTransitionSlide direction:direction region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
  [controller queueTransition:transition];
  [transition release];

  DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
}

#pragma mark -
#pragma mark atrus journal

- (void)_updateAtrusJournal
{
  uint16_t page = [[g_world gameState] unsignedShortForKey:@"aatruspage"];
  release_assert(page > 0);

  if (page == 1) {
    // disable hotspots 7 and 9
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, 7);
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, 9);

    // enable hotspot 10
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, 10);
  } else {
    // enable hotspots 7 and 9
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, 7);
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, 9);

    // disable hotspot 10
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, 10);
  }

  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, page);
}

DEFINE_COMMAND(xaatrusopenbook) { [self _updateAtrusJournal]; }

DEFINE_COMMAND(xaatrusbookback) { [self _returnFromJournal]; }

DEFINE_COMMAND(xaatrusbookprevpage)
{
  uint16_t page = [[g_world gameState] unsignedShortForKey:@"aatruspage"];
  release_assert(page > 1);

  [[g_world gameState] setUnsignedShort:page - 1 forKey:@"aatruspage"];
  [self _flipPageWithTransitionDirection:RXTransitionRight];
}

DEFINE_COMMAND(xaatrusbooknextpage)
{
  uint16_t page = [[g_world gameState] unsignedShortForKey:@"aatruspage"];
  if (page < 10) {
    [[g_world gameState] setUnsignedShort:page + 1 forKey:@"aatruspage"];
    [self _flipPageWithTransitionDirection:RXTransitionLeft];
  }
}

#pragma mark -
#pragma mark catherine journal

- (void)_updateCatherineJournal
{
  uint16_t page = [[g_world gameState] unsignedShortForKey:@"acathpage"];
  release_assert(page > 0);

  if (page == 1) {
    // disable hotspots 7 and 9
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, 7);
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, 9);

    // enable hotspot 10
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, 10);
  } else {
    // enable hotspots 7 and 9
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, 7);
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, 9);

    // disable hotspot 10
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, 10);
  }

  // draw the main page picture
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, page);

  // draw the note edge
  if (page > 1) {
    if (page < 5)
      DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 50);
    else if (page > 5)
      DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 51);
  }

  // draw the telescope combination on page 28
  if (page != 28)
    return;

  // the display origin was determined empirically; the base rect is based on the size of the number overlay pictures
  NSPoint combination_display_origin = NSMakePoint(156.0f, 120.0f);
  NSRect combination_base_rect = NSMakeRect(0.0f, 0.0f, 32.0f, 25.0f);

  uint32_t telescope_combo = [[g_world gameState] unsigned32ForKey:@"tCorrectOrder"];
  NSPoint combination_sampling_origin = NSMakePoint(32.0f, 0.0f);

  for (int i = 0; i < 5; i++) {
    combination_sampling_origin.x = 32.0f * ((telescope_combo & 0x7) - 1);

    [self _drawPictureWithID:13 + i
                       stack:[_card parent]
                 displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];

    combination_display_origin.x += combination_base_rect.size.width;
    telescope_combo >>= 3;
  }
}

DEFINE_COMMAND(xacathopenbook) { [self _updateCatherineJournal]; }

DEFINE_COMMAND(xacathbookback) { [self _returnFromJournal]; }

DEFINE_COMMAND(xacathbookprevpage)
{
  uint16_t page = [[g_world gameState] unsignedShortForKey:@"acathpage"];
  release_assert(page > 1);

  [[g_world gameState] setUnsignedShort:page - 1 forKey:@"acathpage"];
  [self _flipPageWithTransitionDirection:RXTransitionBottom];
}

DEFINE_COMMAND(xacathbooknextpage)
{
  uint16_t page = [[g_world gameState] unsignedShortForKey:@"acathpage"];
  if (page < 49) {
    [[g_world gameState] setUnsignedShort:page + 1 forKey:@"acathpage"];
    [self _flipPageWithTransitionDirection:RXTransitionTop];
  }
}

#pragma mark -
#pragma mark trap book

DEFINE_COMMAND(xtrapbookback) { [self _returnFromJournal]; }

DEFINE_COMMAND(xatrapbookopen)
{
  [[g_world gameState] setUnsignedShort:1 forKey:@"atrap"];

  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);
  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);
  [self _flipPageWithTransitionDirection:RXTransitionLeft];
  DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
}

DEFINE_COMMAND(xatrapbookclose)
{
  [[g_world gameState] setUnsignedShort:0 forKey:@"atrap"];

  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);
  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);
  [self _flipPageWithTransitionDirection:RXTransitionRight];
  DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
}

- (void)_handleTrapBookLink
{
  // get and reset the return card
  RXSimpleCardDescriptor* return_card = [[[g_world gameState] returnCard] retain];
  [[g_world gameState] setReturnCard:nil];

  // if the return stack is rspit, we go to a different card than otherwise
  uint32_t card_rmap;
  if ([return_card->stackKey isEqualToString:@"rspit"]) {
    card_rmap = 13112;
  } else if ([return_card->stackKey isEqualToString:@"ospit"]) {
    card_rmap = 17581;
  } else {
    rx_abort("_handleTrapBookLink got unknown return card stack key '%s'", [return_card->stackKey UTF8String]);
  }

  RXStack* stack = [g_world loadStackWithKey:return_card->stackKey];
  if (!stack) {
    RXLog(kRXLoggingScript, kRXLoggingLevelError, @"aborting script execution: _handleTrapBookLink failed to load stack '%@'", return_card->stackKey);
    _abortProgramExecution = YES;
    return;
  }

  [return_card release];
  [controller setActiveCardWithStack:[stack key] ID:[stack cardIDFromRMAPCode:card_rmap] waitUntilDone:YES];
}

#pragma mark -
#pragma mark introduction sequence

- (void)_enableAtrusJournal { [[g_world gameState] setUnsigned32:1 forKey:@"aatrusbook"]; }

- (void)_enableTrapBook
{
  [[g_world gameState] setUnsigned32:1 forKey:@"atrapbook"];
  intro_atrus_gave_books = YES;
  [[g_world gameState] setUnsigned32:1 forKey:@"intro_atrus_gave_books"];
}

- (void)_disableTrapBook
{
  [[g_world gameState] setUnsigned32:0 forKey:@"atrapbook"];
  intro_cho_took_book = YES;
  [[g_world gameState] setUnsigned32:1 forKey:@"intro_cho_took_book"];
}

- (void)_scheduleInventoryEnableMessages
{
  if (intro_atrus_gave_books)
    return;

  intro_scheduled_atrus_give_books = YES;
  [[g_world gameState] setUnsigned32:1 forKey:@"intro_scheduled_atrus_give_books"];
  [self performSelector:@selector(_enableAtrusJournal) withObject:nil afterDelay:30.0];
  [self performSelector:@selector(_enableTrapBook) withObject:nil afterDelay:68.0];
}

- (void)_scheduleChoTrapBookDisableMessage
{
  if (intro_cho_took_book)
    return;

  intro_scheduled_cho_take_book = YES;
  [[g_world gameState] setUnsigned32:1 forKey:@"intro_scheduled_cho_take_book"];
  [self performSelector:@selector(_disableTrapBook) withObject:nil afterDelay:62.0];
}

DEFINE_COMMAND(xtatrusgivesbooks)
{
  // enable the inventory
  [[g_world gameState] setUnsigned32:1 forKey:@"ainventory"];

  // sneakily make Atrus's journal and the trap book appear during the movie
  [self performSelectorOnMainThread:@selector(_scheduleInventoryEnableMessages) withObject:nil waitUntilDone:NO];
}

DEFINE_COMMAND(xtchotakesbook)
{
  // WORKAROUND: silence the ambient sounds before the last introduction movie plays;
  // an activate SLST command comes after the movie and the movie itself contains ambient sounds
  DISPATCH_COMMAND1(RX_COMMAND_CLEAR_SLST, 0);

  // sneakily remove the trap book when Cho takes it
  [self performSelectorOnMainThread:@selector(_scheduleChoTrapBookDisableMessage) withObject:nil waitUntilDone:NO];
}

#pragma mark -
#pragma mark linking books

- (void)_linkToCard:(RXSimpleCardDescriptor*)scd
{
  // the original engine played 2 linking sound, but I don't like that, so only one!
  //    DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 0, (uint16_t)kRXSoundGainDivisor, 0);

  RXTransition* transition =
      [[RXTransition alloc] initWithType:RXTransitionDissolve direction:0 region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
  [controller queueTransition:transition];
  [transition release];

  [controller setActiveCardWithSimpleDescriptor:scd waitUntilDone:YES];
  [controller showMouseCursor];
}

#pragma mark -
#pragma mark lab journal

- (void)_updateLabJournal
{
  uint16_t page = [[g_world gameState] unsignedShortForKey:@"blabpage"];
  release_assert(page > 0);

  if (page == 1) {
    // disable hotspot 16
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, 16);
  } else {
    // enable hotspot 16
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, 16);
  }

  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, page);

  // draw the dome combination
  if (page == 14) {
    uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
    uint32_t combo_bit = 24;
    NSPoint combination_sampling_origin = NSMakePoint(32.0f, 0.0f);

    // the display origin was determined empirically; the base rect is based on the size of the number overlay pictures
    NSPoint combination_display_origin = NSMakePoint(240.0f, 285.0f);
    NSRect combination_base_rect = NSMakeRect(0.0f, 0.0f, 32.0f, 24.0f);

    while (!(domecombo & (1 << combo_bit)))
      combo_bit--;
    combination_sampling_origin.x = 32.0f * (24 - combo_bit);
    [self _drawPictureWithID:364
                       stack:[_card parent]
                 displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
    combination_display_origin.x += combination_base_rect.size.width;
    combo_bit--;

    while (!(domecombo & (1 << combo_bit)))
      combo_bit--;
    combination_sampling_origin.x = 32.0f * (24 - combo_bit);
    [self _drawPictureWithID:365
                       stack:[_card parent]
                 displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
    combination_display_origin.x += combination_base_rect.size.width;
    combo_bit--;

    while (!(domecombo & (1 << combo_bit)))
      combo_bit--;
    combination_sampling_origin.x = 32.0f * (24 - combo_bit);
    [self _drawPictureWithID:366
                       stack:[_card parent]
                 displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
    combination_display_origin.x += combination_base_rect.size.width;
    combo_bit--;

    while (!(domecombo & (1 << combo_bit)))
      combo_bit--;
    combination_sampling_origin.x = 32.0f * (24 - combo_bit);
    [self _drawPictureWithID:367
                       stack:[_card parent]
                 displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
    combination_display_origin.x += combination_base_rect.size.width;
    combo_bit--;

    while (!(domecombo & (1 << combo_bit)))
      combo_bit--;
    combination_sampling_origin.x = 32.0f * (24 - combo_bit);
    [self _drawPictureWithID:368
                       stack:[_card parent]
                 displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
  }
}

DEFINE_COMMAND(xblabopenbook) { [self _updateLabJournal]; }

DEFINE_COMMAND(xblabbookprevpage)
{
  uint16_t page = [[g_world gameState] unsignedShortForKey:@"blabpage"];
  release_assert(page > 1);

  [[g_world gameState] setUnsignedShort:page - 1 forKey:@"blabpage"];
  [self _flipPageWithTransitionDirection:RXTransitionRight];
}

DEFINE_COMMAND(xblabbooknextpage)
{
  uint16_t page = [[g_world gameState] unsignedShortForKey:@"blabpage"];
  if (page < 22) {
    [[g_world gameState] setUnsignedShort:page + 1 forKey:@"blabpage"];
    [self _flipPageWithTransitionDirection:RXTransitionLeft];
  }
}

#pragma mark -
#pragma mark gehn journal

- (void)_updateGehnJournal
{
  uint16_t page = [[g_world gameState] unsignedShortForKey:@"ogehnpage"];
  release_assert(page > 0);

  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, page);
}

DEFINE_COMMAND(xogehnopenbook) { [self _updateGehnJournal]; }

DEFINE_COMMAND(xogehnbookprevpage)
{
  uint16_t page = [[g_world gameState] unsignedShortForKey:@"ogehnpage"];
  if (page <= 1)
    return;

  [[g_world gameState] setUnsignedShort:page - 1 forKey:@"ogehnpage"];
  [self _flipPageWithTransitionDirection:RXTransitionRight];
}

DEFINE_COMMAND(xogehnbooknextpage)
{
  uint16_t page = [[g_world gameState] unsignedShortForKey:@"ogehnpage"];
  if (page >= 13)
    return;

  [[g_world gameState] setUnsignedShort:page + 1 forKey:@"ogehnpage"];
  [self _flipPageWithTransitionDirection:RXTransitionLeft];
}

#pragma mark -
#pragma mark rebel icon puzzle

- (BOOL)_isIconDepressed:(uint16_t)index
{
  uint32_t icon_bitfield = [[g_world gameState] unsigned32ForKey:@"jicons"];
  return (icon_bitfield & (1U << (index - 1))) ? YES : NO;
}

- (uint32_t)_countDepressedIcons
{
  uint32_t icon_sequence = [[g_world gameState] unsigned32ForKey:@"jiconorder"];
  if (icon_sequence >= (1U << 25))
    return 6;
  else if (icon_sequence >= (1U << 20))
    return 5;
  else if (icon_sequence >= (1U << 15))
    return 4;
  else if (icon_sequence >= (1U << 10))
    return 3;
  else if (icon_sequence >= (1U << 5))
    return 2;
  else if (icon_sequence >= (1U << 1))
    return 1;
  else
    return 0;
}

DEFINE_COMMAND(xicon)
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  // this command sets the variable atemp to 1 if the specified icon is depressed, 0 otherwise;
  // sets atemp to 2 if the icon cannot be depressed

  // must set atemp to 2 if the rebel puzzle has been solved already (jrbook != 0)
  uint32_t jrbook = [[g_world gameState] unsigned32ForKey:@"jrbook"];
  if (jrbook) {
    [[g_world gameState] setUnsigned32:2 forKey:@"atemp"];
    return;
  }

  uint32_t icon_sequence = [[g_world gameState] unsigned32ForKey:@"jiconorder"];
  if ([self _isIconDepressed:argv[0]]) {
    if (argv[0] != (icon_sequence & 0x1F))
      [[g_world gameState] setUnsigned32:2 forKey:@"atemp"];
    else
      [[g_world gameState] setUnsigned32:1 forKey:@"atemp"];
  } else
    [[g_world gameState] setUnsigned32:0 forKey:@"atemp"];
}

DEFINE_COMMAND(xcheckicons)
{
  // this command resets the icon puzzle when a 6th icon is pressed
  if ([self _countDepressedIcons] >= 5) {
    [[g_world gameState] setUnsigned32:0 forKey:@"jicons"];
    [[g_world gameState] setUnsigned32:0 forKey:@"jiconorder"];

    uint16_t sfx = [_card dataSoundIDWithName:@"jfiveicdn"];
    DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, sfx, (uint16_t)kRXSoundGainDivisor, 1);
  }
}

DEFINE_COMMAND(xtoggleicon)
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  // this command toggles the state of a particular icon for the rebel tunnel puzzle

  uint32_t icon_sequence = [[g_world gameState] unsigned32ForKey:@"jiconorder"];
  uint32_t correct_icon_sequence = [[g_world gameState] unsigned32ForKey:@"jiconcorrectorder"];
  uint32_t icon_bitfield = [[g_world gameState] unsigned32ForKey:@"jicons"];
  uint32_t icon_bit = 1U << (argv[0] - 1);

  if (icon_bitfield & icon_bit) {
    [[g_world gameState] setUnsigned32:(icon_bitfield & ~icon_bit)forKey:@"jicons"];
    icon_sequence >>= 5;
  } else {
    [[g_world gameState] setUnsigned32:(icon_bitfield | icon_bit)forKey:@"jicons"];
    icon_sequence = icon_sequence << 5 | argv[0];
  }

  [[g_world gameState] setUnsigned32:icon_sequence forKey:@"jiconorder"];

  if (icon_sequence == correct_icon_sequence)
    [[g_world gameState] setUnsignedShort:1 forKey:@"jrbook"];
}

DEFINE_COMMAND(xjtunnel103_pictfix)
{
  // this command needs to overlay pictures of depressed icons based on the value of jicons

  // this command does not use the helper _isIconDepressed method to avoid fetching jicons multiple times
  uint32_t icon_bitfield = [[g_world gameState] unsigned32ForKey:@"jicons"];

  if (icon_bitfield & 1U)
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 2);
  if (icon_bitfield & (1U << 1))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 3);
  if (icon_bitfield & (1U << 2))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 4);
  if (icon_bitfield & (1U << 3))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 5);
  if (icon_bitfield & (1U << 22))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 6);
  if (icon_bitfield & (1U << 23))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 7);
  if (icon_bitfield & (1U << 24))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 8);
}

DEFINE_COMMAND(xjtunnel104_pictfix)
{
  // this command needs to overlay pictures of depressed icons based on the value of jicons

  // this command does not use the helper _isIconDepressed method to avoid fetching jicons multiple times
  uint32_t icon_bitfield = [[g_world gameState] unsigned32ForKey:@"jicons"];

  if (icon_bitfield & (1U << 9))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 2);
  if (icon_bitfield & (1U << 10))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 3);
  if (icon_bitfield & (1U << 11))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 4);
  if (icon_bitfield & (1U << 12))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 5);
  if (icon_bitfield & (1U << 13))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 6);
  if (icon_bitfield & (1U << 14))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 7);
  if (icon_bitfield & (1U << 15))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 8);
  if (icon_bitfield & (1U << 16))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 9);
}

DEFINE_COMMAND(xjtunnel105_pictfix)
{
  // this command needs to overlay pictures of depressed icons based on the value of jicons

  // this command does not use the helper _isIconDepressed method to avoid fetching jicons multiple times
  uint32_t icon_bitfield = [[g_world gameState] unsigned32ForKey:@"jicons"];

  if (icon_bitfield & (1U << 3))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 2);
  if (icon_bitfield & (1U << 4))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 3);
  if (icon_bitfield & (1U << 5))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 4);
  if (icon_bitfield & (1U << 6))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 5);
  if (icon_bitfield & (1U << 7))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 6);
  if (icon_bitfield & (1U << 8))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 7);
  if (icon_bitfield & (1U << 9))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 8);
}

DEFINE_COMMAND(xjtunnel106_pictfix)
{
  // this command needs to overlay pictures of depressed icons based on the value of jicons

  // this command does not use the helper _isIconDepressed method to avoid fetching jicons multiple times
  uint32_t icon_bitfield = [[g_world gameState] unsigned32ForKey:@"jicons"];

  if (icon_bitfield & (1U << 16))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 2);
  if (icon_bitfield & (1U << 17))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 3);
  if (icon_bitfield & (1U << 18))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 4);
  if (icon_bitfield & (1U << 19))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 5);
  if (icon_bitfield & (1U << 20))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 6);
  if (icon_bitfield & (1U << 21))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 7);
  if (icon_bitfield & (1U << 22))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 8);
  if (icon_bitfield & (1U << 23))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 9);
}

DEFINE_COMMAND(xreseticons)
{
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@xreseticons was called, resetting the entire rebel icon puzzle state", logPrefix);
#endif

  [[g_world gameState] setUnsigned32:0 forKey:@"jiconorder"];
  [[g_world gameState] setUnsigned32:0 forKey:@"jicons"];
  [[g_world gameState] setUnsignedShort:0 forKey:@"jrbook"];
}

#pragma mark -
#pragma mark jungle elevator

static uint32_t const k_jungle_elevator_mid_rmap = 123764;
static uint32_t const k_jungle_elevator_top_rmap = 124311;
static uint32_t const k_jungle_elevator_bottom_rmap = 123548;

static float const k_jungle_elevator_trigger_magnitude = 16.0f;

- (void)_handleJungleElevatorMouth
{
  // if the mouth is open, we need to close it before going up or down
  if ([[g_world gameState] unsignedShortForKey:@"jwmouth"]) {
    [[g_world gameState] setUnsignedShort:0 forKey:@"jwmouth"];

    // play the close mouth movie
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 3);

    // play the mouth control lever movie
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 8);
  }
}

DEFINE_COMMAND(xhandlecontrolup)
{
  NSRect mouse_vector = [controller mouseVector];
  [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];

  NSRect scale_rect = RXRenderScaleRect();
  float trigger_mag = k_jungle_elevator_trigger_magnitude * scale_rect.size.height;

  // track the mouse until the mouse button is released
  while (isfinite(mouse_vector.size.width)) {
    if (mouse_vector.size.height < 0.0f && fabsf(mouse_vector.size.height) >= trigger_mag) {
      // play the switch down movie
      DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 1);

      // play the going down movie
      DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE, 2);

      // wait 3.333 seconds
      usleep(3333 * 1000);

      // activate SLST 1 (which is the ambient mix inside the elevator)
      DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_SLST, 1);

      // wait for the movie to finish
      DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);

      // go to the middle jungle elevator card
      DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, [[_card parent] cardIDFromRMAPCode:k_jungle_elevator_mid_rmap]);

      // we're all done
      break;
    }

    [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];
    mouse_vector = [controller mouseVector];

    usleep(kRunloopPeriodMicroseconds);
  }
}

DEFINE_COMMAND(xhandlecontrolmid)
{
  NSRect mouse_vector = [controller mouseVector];
  [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];

  NSRect scale_rect = RXRenderScaleRect();
  float trigger_mag = k_jungle_elevator_trigger_magnitude * scale_rect.size.height;

  // track the mouse until the mouse button is released
  while (isfinite(mouse_vector.size.width)) {
    if (mouse_vector.size.height >= trigger_mag) {
      // play the switch up movie
      DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 7);

      [self _handleJungleElevatorMouth];

      // play the going up movie
      DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE, 5);

      // wait 5 seconds
      usleep(5 * 1E6);

      // activate SLST 2 (which is the ambient mix for the upper jungle level)
      DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_SLST, 2);

      // wait for the movie to finish
      DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 5);

      // go to the top jungle elevator card
      DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, [[_card parent] cardIDFromRMAPCode:k_jungle_elevator_top_rmap]);

      // we're all done
      break;
    } else if (mouse_vector.size.height < 0.0f && fabsf(mouse_vector.size.height) >= k_jungle_elevator_trigger_magnitude) {
      // play the switch down movie
      DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 6);

      [self _handleJungleElevatorMouth];

      // play the going down movie
      DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 4);

      // go to the bottom jungle elevator card
      DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, [[_card parent] cardIDFromRMAPCode:k_jungle_elevator_bottom_rmap]);

      // we're all done
      break;
    }

    [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];
    mouse_vector = [controller mouseVector];

    usleep(kRunloopPeriodMicroseconds);
  }
}

DEFINE_COMMAND(xhandlecontroldown)
{
  NSRect mouse_vector = [controller mouseVector];
  [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];

  NSRect scale_rect = RXRenderScaleRect();
  float trigger_mag = k_jungle_elevator_trigger_magnitude * scale_rect.size.height;

  // track the mouse until the mouse button is released
  while (isfinite(mouse_vector.size.width)) {
    if (mouse_vector.size.height >= trigger_mag) {
      // play the switch up movie
      DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 1);

      // play the going up movie
      DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);

      // go to the middle jungle elevator card
      DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, [[_card parent] cardIDFromRMAPCode:k_jungle_elevator_mid_rmap]);

      // we're all done
      break;
    }

    [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];
    mouse_vector = [controller mouseVector];

    usleep(kRunloopPeriodMicroseconds);
  }
}

#pragma mark -
#pragma mark boiler central

DEFINE_COMMAND(xvalvecontrol)
{
  uint16_t valve_state = [[g_world gameState] unsignedShortForKey:@"bvalve"];

  [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];

  NSRect scale_rect = RXRenderScaleRect();
  NSRect mouse_vector = [controller mouseVector];
  mouse_vector.size.width /= scale_rect.size.width;
  mouse_vector.size.height /= scale_rect.size.height;

  // track the mouse until the mouse button is released
  while (isfinite(mouse_vector.size.width)) {
    float theta = 180.0f * atan2f(mouse_vector.size.height, mouse_vector.size.width) * M_1_PI;
    float r = sqrtf((mouse_vector.size.height * mouse_vector.size.height) + (mouse_vector.size.width * mouse_vector.size.width));

    switch (valve_state) {
    case 0:
      if (theta <= -90.0f && theta >= -150.0f && r >= 40.0f) {
        valve_state = 1;
        [[g_world gameState] setUnsignedShort:valve_state forKey:@"bvalve"];
        DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);
        DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
      }
      break;
    case 1:
      if (theta <= 80.0f && theta >= -10.0f && r >= 40.0f) {
        valve_state = 0;
        [[g_world gameState] setUnsignedShort:valve_state forKey:@"bvalve"];
        DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 3);
        DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
      } else if ((theta <= -60.0f || theta >= 160.0f) && r >= 20.0f) {
        valve_state = 2;
        [[g_world gameState] setUnsignedShort:valve_state forKey:@"bvalve"];
        DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 1);
        DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
      }
      break;
    case 2:
      if (theta <= 30.0f && theta >= -30.0f && r >= 20.0f) {
        valve_state = 1;
        [[g_world gameState] setUnsignedShort:valve_state forKey:@"bvalve"];
        DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 4);
        DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
      }
      break;
    }

    // if we did hide the mouse, it means we played one of the valve movies; if so, break out of the mouse tracking loop
    if (_did_hide_mouse) {
      break;
    }

    [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];

    mouse_vector = [controller mouseVector];
    mouse_vector.size.width /= scale_rect.size.width;
    mouse_vector.size.height /= scale_rect.size.height;

    usleep(kRunloopPeriodMicroseconds);
  }

  // if we set the valve to position 1 (power to the boiler), we need to update the boiler state
  if (valve_state == 1) {
    if ([[g_world gameState] unsignedShortForKey:@"bidvlv"]) {
      // power is going to the water pump

      // adjust the water's state to match the water pump's flex pipe state
      uint16_t flex_pipe = [[g_world gameState] unsignedShortForKey:@"bblrarm"];
      if (flex_pipe) {
        // flex pipe is disconnected
        [[g_world gameState] setUnsignedShort:0 forKey:@"bheat"];
        [[g_world gameState] setUnsignedShort:0 forKey:@"bblrwtr"];
      } else {
        // flex pipe is connected
        if ([[g_world gameState] unsignedShortForKey:@"bblrvalve"])
          [[g_world gameState] setUnsignedShort:1 forKey:@"bheat"];
        [[g_world gameState] setUnsignedShort:1 forKey:@"bblrwtr"];
      }
    } else {
      // power is going to the platform

      // adjust the platform's state to match the platform control switch's state
      uint16_t platform_switch = [[g_world gameState] unsignedShortForKey:@"bblrsw"];
      [[g_world gameState] setUnsignedShort:(platform_switch) ? 0 : 1 forKey:@"bblrgrt"];
    }
  }
}

DEFINE_COMMAND(xbchipper)
{
  [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];

  uint16_t valve_state = [[g_world gameState] unsignedShortForKey:@"bvalve"];
  if (valve_state != 2)
    return;

  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);
}

DEFINE_COMMAND(xbupdateboiler)
{
  // when xbupdateboiler gets called, the boiler state variables will have been updated
  uint16_t heat = [[g_world gameState] unsignedShortForKey:@"bheat"];
  uint16_t platform = [[g_world gameState] unsignedShortForKey:@"bblrgrt"];

  if (!heat) {
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 7);
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 8);
  } else {
    if (platform)
      DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_MLST_AND_START, 7);
    else
      DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_MLST_AND_START, 8);
  }

  DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
}

DEFINE_COMMAND(xbchangeboiler)
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  // when xbchangeboiler gets called, the boiler state variables have not yet been updated
  // the following variables therefore represent the *previous* state

  uint16_t heat = [[g_world gameState] unsignedShortForKey:@"bheat"];
  uint16_t water = [[g_world gameState] unsignedShortForKey:@"bblrwtr"];
  uint16_t platform = [[g_world gameState] unsignedShortForKey:@"bblrgrt"];

  if (argv[0] == 1) {
    if (!water) {
      if (platform)
        DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 12, 0);
      else
        DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 10, 0);
    } else {
      if (heat) {
        if (platform)
          DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 22, 0);
        else
          DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 19, 0);
      } else {
        if (platform)
          DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 16, 0);
        else
          DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 13, 0);
      }
    }
  } else if (argv[0] == 2) {
    if (heat) {
      // we are turning off the heat
      if (water) {
        if (platform)
          DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 23, 0);
        else
          DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 20, 0);
      }
    } else {
      // we are turning on the heat
      if (water) {
        if (platform)
          DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 18, 0);
        else
          DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 15, 0);
      }
    }
  } else if (argv[0] == 3) {
    if (platform) {
      // we are lowering the platform
      if (water) {
        if (heat)
          DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 24, 0);
        else
          DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 17, 0);
      } else
        DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 11, 0);
    } else {
      // we are raising the platform
      if (water) {
        if (heat)
          DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 21, 0);
        else
          DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 14, 0);
      } else
        DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, 9, 11);
    }
  }

  if (argc > 1)
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_SLST, argv[1]);
  else if (argv[0] == 2)
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_SLST, 1);

  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 11);
}

DEFINE_COMMAND(xsoundplug)
{
  uint16_t heat = [[g_world gameState] unsignedShortForKey:@"bheat"];
  uint16_t boiler_inactive = [[g_world gameState] unsignedShortForKey:@"bcratergg"];

  if (heat)
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_SLST, 1);
  else if (boiler_inactive)
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_SLST, 2);
  else
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_SLST, 3);
}

#pragma mark -
#pragma mark village school

DEFINE_COMMAND(xjschool280_resetleft) { [[g_world gameState] setUnsignedShort:0 forKey:@"jleftpos"]; }

DEFINE_COMMAND(xjschool280_resetright) { [[g_world gameState] setUnsignedShort:0 forKey:@"jrightpos"]; }

- (void)_configureDoomedVillagerMovie:(NSNumber*)stepsNumber
{
  uint16_t level_of_doom;
  uintptr_t k;
  if ([[g_world gameState] unsignedShortForKey:@"jwharkpos"] == 1) {
    level_of_doom = [[g_world gameState] unsignedShortForKey:@"jleftpos"];
    k = 3;
  } else {
    level_of_doom = [[g_world gameState] unsignedShortForKey:@"jrightpos"];
    k = 5;
  }

  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)k);

  // compute the duration per tick
  QTTime duration = [movie duration];
  duration.timeValue /= 19;

  // set the movie's playback range
  QTTimeRange movie_range = QTMakeTimeRange(QTMakeTime(duration.timeValue * level_of_doom, duration.timeScale),
                                            QTMakeTime(duration.timeValue * [stepsNumber unsignedShortValue], duration.timeScale));
  [movie setPlaybackSelection:movie_range];
}

DEFINE_COMMAND(xschool280_playwhark)
{
  // cache the game state object
  RXGameState* state = [g_world gameState];

  // generate a random number between 1 and 10
  uint16_t the_number = rx_rnd_range(1, 10);
#if defined(DEBUG)
  if (!_disableScriptLogging)
    RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@rolled a %hu", logPrefix, the_number);
#endif

  NSString* villager_position_variable;
  uint16_t spin_mlst;
  uint16_t overlay_plst;
  uint16_t doom_mlst;
  uint16_t snak_mlst;
  uint16_t blsts_to_activate[2];
  if ([state unsignedShortForKey:@"jwharkpos"] == 1) {
    // to the left
    villager_position_variable = @"jleftpos";
    spin_mlst = 1;
    overlay_plst = 12;
    doom_mlst = 3;
    snak_mlst = 4;
    blsts_to_activate[0] = 2;
    blsts_to_activate[1] = 4;
  } else {
    // to the right
    villager_position_variable = @"jrightpos";
    spin_mlst = 2;
    overlay_plst = 13;
    doom_mlst = 5;
    snak_mlst = 6;
    blsts_to_activate[0] = 1;
    blsts_to_activate[1] = 3;
  }

  // to the left
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, spin_mlst);

  // in a transaction, re-blit the base picture, blit the overlay picture, blit the number picture and disable the spin movie
  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1);
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, overlay_plst);
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1 + the_number);
  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, spin_mlst);
  DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);

  // get the villager's position
  uint16_t level_of_doom = [state unsignedShortForKey:villager_position_variable];

  // configure the doomed villager movie and play it
  [self performSelectorOnMainThread:@selector(_configureDoomedVillagerMovie:) withObject:[NSNumber numberWithUnsignedShort:the_number] waitUntilDone:YES];
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, doom_mlst);

  // update the villager's doom level
  [state setUnsignedShort:level_of_doom + the_number forKey:villager_position_variable];

  // is it time for a snack?
  if (level_of_doom + the_number > 19) {
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, snak_mlst);

    DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, doom_mlst);
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, snak_mlst);
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1);
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, overlay_plst);
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1 + the_number);
    DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);

    [state setUnsignedShort:0 forKey:villager_position_variable];
  }

  // disable rotateleft and enable rotateright
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_BLST, blsts_to_activate[0]);
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_BLST, blsts_to_activate[1]);
}

#pragma mark -
#pragma mark common dome methods

- (void)handleVisorButtonPressForDome:(NSString*)dome
{
  uint16_t dome_state = [[g_world gameState] unsignedShortForKey:dome];
  if (dome_state == 3) {
    uintptr_t k = 2;
    RXMovie* button_movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)k);
    [self performSelectorOnMainThread:@selector(_unmuteMovie:) withObject:button_movie waitUntilDone:NO];
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);
  }
}

- (void)checkDome:(NSString*)dome mutingVisorButtonMovie:(BOOL)mute_visor
{
  // when was the movie at the time?
  uintptr_t k = 1;
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)k);

  NSTimeInterval movie_position;
  QTGetTimeInterval([movie _noLockCurrentTime], &movie_position);

  NSTimeInterval duration;
  QTGetTimeInterval([movie duration], &duration);

  // get the button movie
  k = 2;
  RXMovie* button_movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)k);

// did we hit the golden eye frame?
#if defined(DEBUG)
  double mouse_ts_s = [controller mouseTimestamp];
  double event_delay = RXTimingTimestampDelta(RXTimingNow(), RXTimingOffsetTimestamp(0, mouse_ts_s));
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@movie_position=%f, event_delay=%f, position-delay=%f", logPrefix, movie_position, event_delay,
        movie_position - event_delay);
#endif
  // if (time > 2780 || time < 200)
  if (movie_position >= 4.58) {
    [[g_world gameState] setUnsignedShort:1 forKey:@"domecheck"];

    // mute button movie if requested and start asynchronous playback of the visor button movie
    if (mute_visor)
      [self performSelectorOnMainThread:@selector(_muteMovie:) withObject:button_movie waitUntilDone:NO];
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE, 2);
  } else {
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);
  }
}

- (void)drawSlidersForDome:(NSString*)dome minHotspotID:(uintptr_t)min_id
{
  // cache the hotspots ID map
  NSMapTable* hotspots_map = [_card hotspotsIDMap];

  // get the dome slider and slider background pictures
  uint16_t slider_suffix = 190;
  if ([dome isEqualToString:@"pdome"])
    slider_suffix = 25;
  NSString* slider_bmp_name = [NSString stringWithFormat:@"%hu_%Csliders.%hu", [[_card descriptor] ID], [dome characterAtIndex:0], slider_suffix];
  NSString* sliderbg_bmp_name = [NSString stringWithFormat:@"%hu_%Csliderbg.%hu", [[_card descriptor] ID], [dome characterAtIndex:0], slider_suffix];

  uint16_t sliders = [[_card parent] bitmapIDForName:slider_bmp_name];
  uint16_t background = [[_card parent] bitmapIDForName:sliderbg_bmp_name];

  // begin a screen update transaction
  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);

  // draw the background; 220 x 69 is the slider background dimension
  NSRect display_rect = RXMakeCompositeDisplayRect(dome_slider_background_position.x, dome_slider_background_position.y,
                                                   dome_slider_background_position.x + 220, dome_slider_background_position.y + 69);
  [self _drawPictureWithID:background stack:[_card parent] displayRect:display_rect samplingRect:NSMakeRect(0.0f, 0.0f, 0.0f, 0.0f)];

  // draw the sliders
  uintptr_t k = 0;
  for (int i = 0; i < 5; i++) {
    while (k < 25 && !(sliders_state & (1 << (24 - k))))
      k++;

    RXHotspot* h = (RXHotspot*)NSMapGet(hotspots_map, (void*)(k + min_id));
    k++;

    rx_core_rect_t hotspot_rect = [h coreFrame];
    display_rect = RXMakeCompositeDisplayRectFromCoreRect(hotspot_rect);
    NSRect sampling_rect = NSMakeRect(hotspot_rect.left - dome_slider_background_position.x, hotspot_rect.top - dome_slider_background_position.y,
                                      display_rect.size.width, display_rect.size.height);
    [self _drawPictureWithID:sliders stack:[_card parent] displayRect:display_rect samplingRect:sampling_rect];
  }

  // end the screen update transaction
  DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
}

- (void)resetSlidersForDome:(NSString*)dome
{
  // cache the tic sound
  RXDataSound* tic_sound = [RXDataSound new];
  tic_sound->parent = [[_card descriptor] parent];
  tic_sound->twav_id = [_card dataSoundIDWithName:@"aBigTic"];
  tic_sound->gain = 1.0f;
  tic_sound->pan = 0.5f;

  // cache the minimum slider hotspot ID
  RXHotspot* min_hotspot = (RXHotspot*)NSMapGet([_card hotspotsNameMap], @"s1");
  release_assert(min_hotspot);
  uintptr_t min_hotspot_id = [min_hotspot ID];

  uint32_t first_bit = 0x0;
  while (first_bit < 25) {
    if (sliders_state & (1 << first_bit))
      break;
    first_bit++;
  }

  // disable transition dequeueing to work around the fact this external can be called by close card scripts after a transition has been queued
  [controller disableTransitionDequeueing];

  // let's play the "push the bits" game until the sliders have been reset
  while (sliders_state != 0x1F00000) {
    if (sliders_state & (1 << (first_bit + 1))) {
      if (sliders_state & (1 << (first_bit + 2))) {
        if (sliders_state & (1 << (first_bit + 3))) {
          if (sliders_state & (1 << (first_bit + 4))) {
            sliders_state = (sliders_state & ~(1 << (first_bit + 4))) | (1 << (first_bit + 5));
          }
          sliders_state = (sliders_state & ~(1 << (first_bit + 3))) | (1 << (first_bit + 4));
        }
        sliders_state = (sliders_state & ~(1 << (first_bit + 2))) | (1 << (first_bit + 3));
      }
      sliders_state = (sliders_state & ~(1 << (first_bit + 1))) | (1 << (first_bit + 2));
    }
    sliders_state = (sliders_state & ~(1 << first_bit)) | (1 << (first_bit + 1));

    // play the tic sound and update the slider graphics
    [controller playDataSound:tic_sound];
    [self drawSlidersForDome:dome minHotspotID:min_hotspot_id];

    // sleep some arbitrary amount of time (until the next frame); this value is to be tweaked visually
    usleep(20000);
    first_bit++;
  }

  // re-enable transition dequeueing
  [controller enableTransitionDequeueing];

  // check if the sliders match the dome configuration
  uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
  if (sliders_state == domecombo) {
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"resetsliders") ID]);
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"opendome") ID]);
  } else {
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"resetsliders") ID]);
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"opendome") ID]);
  }

  [tic_sound release];
}

- (RXHotspot*)domeSliderHotspotForDome:(NSString*)dome
                         mousePosition:(NSPoint)mouse_position
                         activeHotspot:(RXHotspot*)active_hotspot
                          minHotspotID:(uintptr_t)min_id
{
  // cache the hotspots ID map
  NSMapTable* hotspots_map = [_card hotspotsIDMap];

  uintptr_t boundary_hotspot_id = 0;
  for (uintptr_t k = 0; k < 25; k++) {
    RXHotspot* hotspot = (RXHotspot*)NSMapGet(hotspots_map, (void*)(k + min_id));

    // look for the boundary hotspot for a move-to-right update here since we are doing a forward scan already
    if (active_hotspot && !boundary_hotspot_id && (k + min_id) > [active_hotspot ID] && (sliders_state & (1 << (24 - k))))
      boundary_hotspot_id = [hotspot ID];

    // if there is an active hotspot, adjust the mouse position's y
    // coordinate to be inside the hotspot (we ignore cursor height
    // when dragging a slider)
    if (active_hotspot)
      mouse_position.y = [hotspot worldFrame].origin.y + 1;

    if (NSMouseInRect(mouse_position, [hotspot worldFrame], NO)) {
      // we found the hotspot over which the mouse currently is; this ends
      // the forward search

      if (!active_hotspot) {
        // there is no active hotspot, meaning we're not dragging a
        // slider

        // if there is no slider in this slot, return nil (nothing here,
        // basically)
        if (!(sliders_state & (1 << (24 - k))))
          hotspot = nil;
      } else {
        // a slider is being dragged (there is an active hotspot)

        // we only need to do boundary checking if the hotspot under the
        // mouse is not the active hotspot
        if (hotspot != active_hotspot) {
          if ([hotspot ID] > [active_hotspot ID]) {
            // moving to the right; if the boundary hotspot is on
            // the right of the active hotspot, snap the hotspot we
            // return to the boundary hotspot
            if (boundary_hotspot_id > [active_hotspot ID])
              hotspot = (RXHotspot*)NSMapGet(hotspots_map, (void*)(boundary_hotspot_id - 1));
          } else {
            // moving to the left; need to find the left boundary
            // by doing a backward scan from the active hotspot to
            // the current hotspot
            boundary_hotspot_id = 0;
            intptr_t reverse_scan_limit = [hotspot ID] - min_id;
            for (intptr_t k2 = [active_hotspot ID] - 1 - min_id; k2 >= reverse_scan_limit; k2--) {
              if ((sliders_state & (1 << (24 - k2)))) {
                boundary_hotspot_id = k2 + min_id;
                break;
              }
            }

            if (boundary_hotspot_id)
              hotspot = (RXHotspot*)NSMapGet(hotspots_map, (void*)(boundary_hotspot_id + 1));
          }
        }
      }

      return hotspot;
    }
  }

  return nil;
}

- (void)handleSliderDragForDome:(NSString*)dome
{
  // cache the minimum slider hotspot ID
  RXHotspot* min_hotspot = (RXHotspot*)NSMapGet([_card hotspotsNameMap], @"s1");
  release_assert(min_hotspot);
  uintptr_t min_hotspot_id = [min_hotspot ID];

  // determine if the mouse was on one of the active slider hotspots when it was pressed; if not, we're done
  NSRect mouse_vector = [controller mouseVector];
  RXHotspot* active_hotspot = [self domeSliderHotspotForDome:dome mousePosition:mouse_vector.origin activeHotspot:nil minHotspotID:min_hotspot_id];
  if (!active_hotspot || !active_hotspot->enabled)
    return;

  // set the cursor to the closed hand cursor
  [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];

  // cache the tic sound
  RXDataSound* tic_sound = [RXDataSound new];
  tic_sound->parent = [[_card descriptor] parent];
  tic_sound->twav_id = [_card dataSoundIDWithName:@"aBigTic"];
  tic_sound->gain = 1.0f;
  tic_sound->pan = 0.5f;

  // track the mouse, updating the position of the slider as appropriate
  while (isfinite(mouse_vector.size.width)) {
    // where are we now?
    RXHotspot* hotspot = [self domeSliderHotspotForDome:dome
                                          mousePosition:NSOffsetRect(mouse_vector, mouse_vector.size.width, mouse_vector.size.height).origin
                                          activeHotspot:active_hotspot
                                           minHotspotID:min_hotspot_id];
    if (hotspot && hotspot != active_hotspot) {
      // play the tic sound
      [controller playDataSound:tic_sound];

      // disable the old and enable the new
      sliders_state = (sliders_state & ~(1 << (24 - ([active_hotspot ID] - min_hotspot_id)))) | (1 << (24 - ([hotspot ID] - min_hotspot_id)));
      active_hotspot = hotspot;

      // draw the new slider state
      [self drawSlidersForDome:dome minHotspotID:min_hotspot_id];
    }

    // update the mouse cursor and vector
    [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];
    mouse_vector = [controller mouseVector];

    usleep(kRunloopPeriodMicroseconds);
  }

  // check if the sliders match the dome configuration
  uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
  if (sliders_state == domecombo) {
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"resetsliders") ID]);
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"opendome") ID]);
  } else {
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"resetsliders") ID]);
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"opendome") ID]);
  }

  [tic_sound release];
}

- (void)handleMouseOverSliderForDome:(NSString*)dome
{
  RXHotspot* min_hotspot = (RXHotspot*)NSMapGet([_card hotspotsNameMap], @"s1");
  release_assert(min_hotspot);
  uintptr_t min_hotspot_id = [min_hotspot ID];

  RXHotspot* active_hotspot = [self domeSliderHotspotForDome:dome mousePosition:[controller mouseVector].origin activeHotspot:nil minHotspotID:min_hotspot_id];
  if (active_hotspot)
    [controller setMouseCursor:RX_CURSOR_OPEN_HAND];
  else
    [controller setMouseCursor:RX_CURSOR_FORWARD];
}

#pragma mark -
#pragma mark bdome dome

DEFINE_COMMAND(xbscpbtn) { [self handleVisorButtonPressForDome:@"bdome"]; }

DEFINE_COMMAND(xbisland_domecheck) { [self checkDome:@"bdome" mutingVisorButtonMovie:NO]; }

DEFINE_COMMAND(xbisland190_opencard)
{
  // check if the sliders match the dome configuration
  uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
  if (sliders_state == domecombo) {
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"resetsliders") ID]);
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"opendome") ID]);
  }
}

DEFINE_COMMAND(xbisland190_resetsliders)
{
  dome_slider_background_position.x = 200;
  [self resetSlidersForDome:@"bdome"];
}

DEFINE_COMMAND(xbisland190_slidermd)
{
  dome_slider_background_position.x = 200;
  [self handleSliderDragForDome:@"bdome"];
}

DEFINE_COMMAND(xbisland190_slidermw) { [self handleMouseOverSliderForDome:@"bdome"]; }

#pragma mark -
#pragma mark gdome dome

DEFINE_COMMAND(xgscpbtn) { [self handleVisorButtonPressForDome:@"gdome"]; }

DEFINE_COMMAND(xgisland1490_domecheck) { [self checkDome:@"gdome" mutingVisorButtonMovie:NO]; }

DEFINE_COMMAND(xgisland25_opencard)
{
  // check if the sliders match the dome configuration
  uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
  if (sliders_state == domecombo) {
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"resetsliders") ID]);
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"opendome") ID]);
  }
}

DEFINE_COMMAND(xgisland25_resetsliders)
{
  dome_slider_background_position.x = 200;
  [self resetSlidersForDome:@"gdome"];
}

DEFINE_COMMAND(xgisland25_slidermd)
{
  dome_slider_background_position.x = 200;
  [self handleSliderDragForDome:@"gdome"];
}

DEFINE_COMMAND(xgisland25_slidermw) { [self handleMouseOverSliderForDome:@"gdome"]; }

#pragma mark -
#pragma mark jspit dome

DEFINE_COMMAND(xjscpbtn) { [self handleVisorButtonPressForDome:@"jdome"]; }

DEFINE_COMMAND(xjisland3500_domecheck) { [self checkDome:@"jdome" mutingVisorButtonMovie:YES]; }

DEFINE_COMMAND(xjdome25_resetsliders)
{
  dome_slider_background_position.x = 200;
  [self resetSlidersForDome:@"jdome"];
}

DEFINE_COMMAND(xjdome25_slidermd)
{
  dome_slider_background_position.x = 200;
  [self handleSliderDragForDome:@"jdome"];
}

DEFINE_COMMAND(xjdome25_slidermw) { [self handleMouseOverSliderForDome:@"jdome"]; }

#pragma mark -
#pragma mark pdome dome

DEFINE_COMMAND(xpscpbtn) { [self handleVisorButtonPressForDome:@"pdome"]; }

DEFINE_COMMAND(xpisland290_domecheck) { [self checkDome:@"pdome" mutingVisorButtonMovie:NO]; }

DEFINE_COMMAND(xpisland25_opencard)
{
  // check if the sliders match the dome configuration
  uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
  if (sliders_state == domecombo) {
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"resetsliders") ID]);
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"opendome") ID]);
  }
}

DEFINE_COMMAND(xpisland25_resetsliders)
{
  dome_slider_background_position.x = 198;
  [self resetSlidersForDome:@"pdome"];
}

DEFINE_COMMAND(xpisland25_slidermd)
{
  dome_slider_background_position.x = 198;
  [self handleSliderDragForDome:@"pdome"];
}

DEFINE_COMMAND(xpisland25_slidermw) { [self handleMouseOverSliderForDome:@"pdome"]; }

#pragma mark -
#pragma mark tspit dome

DEFINE_COMMAND(xtscpbtn) { [self handleVisorButtonPressForDome:@"tdome"]; }

DEFINE_COMMAND(xtisland4990_domecheck) { [self checkDome:@"tdome" mutingVisorButtonMovie:NO]; }

DEFINE_COMMAND(xtisland5056_opencard)
{
  // check if the sliders match the dome configuration
  uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
  if (sliders_state == domecombo) {
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"resetsliders") ID]);
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"opendome") ID]);
  }
}

DEFINE_COMMAND(xtisland5056_resetsliders)
{
  dome_slider_background_position.x = 200;
  [self resetSlidersForDome:@"tdome"];
}

DEFINE_COMMAND(xtisland5056_slidermd)
{
  dome_slider_background_position.x = 200;
  [self handleSliderDragForDome:@"tdome"];
}

DEFINE_COMMAND(xtisland5056_slidermw) { [self handleMouseOverSliderForDome:@"tdome"]; }

#pragma mark -
#pragma mark power dome

typedef enum {
  BLUE_MARBLE = 1,
  GREEN_MARBLE,
  ORANGE_MARBLE,
  PURPLE_MARBLE,
  RED_MARBLE,
  YELLOW_MARBLE
} rx_fire_marble_t;

static uint32_t const marble_offset_matrix[2][5] = {{134, 202, 270, 338, 406}, // x
                                                    {24, 92, 159, 227, 295},   // y
};

static uint32_t const tiny_marble_offset_matrix[2][5] = {{246, 269, 293, 316, 340}, // x
                                                         {263, 272, 284, 295, 309}, // y
};

static uint32_t const tiny_marble_receptable_position_vectors[2][6] = {
    //   red    orange  yellow  green   blue    violet
    {376, 378, 380, 382, 384, 386}, // x
    {253, 257, 261, 265, 268, 273}, // y
};

static float const marble_size = 13.5f;

- (void)_drawTinyMarbleWithPosition:(uint32_t)marble_pos index:(uint32_t)index waffle:(uint32_t)waffle
{
  uint32_t marble_x = (marble_pos >> 16) - 1;
  uint32_t marble_y = (marble_pos & 0xFFFF) - 1;

  // create a RXDynamicPicture object and queue it for rendering
  NSRect sampling_rect = NSMakeRect(0.f, index * 2, 4.f, 2.f);

  rx_core_rect_t core_display_rect;
  if (marble_pos == 0) {
    core_display_rect.left = tiny_marble_receptable_position_vectors[0][index];
    core_display_rect.top = tiny_marble_receptable_position_vectors[1][index];
  } else {
    // if the waffle is not up, we must not draw the tiny marble
    if (waffle != 0)
      return;

    NSPoint p1 = NSMakePoint(11834.f / 39.f, 4321.f / 39.f);
    NSPoint p2 = NSMakePoint(tiny_marble_offset_matrix[0][marble_x / 5] + 5 * (marble_x % 5), tiny_marble_offset_matrix[1][0]);
    float y = tiny_marble_offset_matrix[1][marble_y / 5] + 2 * (marble_y % 5);
    float t = (y - p1.y) / (p2.y - p1.y + 0.000001);
    float x = p2.x * t + p1.x * (1.f - t);

    core_display_rect.left = x - 1;
    core_display_rect.top = y;
  }
  core_display_rect.right = core_display_rect.left + 4;
  core_display_rect.bottom = core_display_rect.top + 2;

  RXDynamicPicture* picture = [[RXDynamicPicture alloc] initWithTexture:tiny_marble_atlas
                                                           samplingRect:sampling_rect
                                                             renderRect:RXMakeCompositeDisplayRectFromCoreRect(core_display_rect)
                                                                  owner:self];
  [controller queuePicture:picture];
  [picture release];
}

DEFINE_COMMAND(xt7600_setupmarbles)
{
  // this command draws the "tiny marbles" bitmaps on tspit 227

  // load the tiny marble atlas if we haven't done so yet
  if (!tiny_marble_atlas) {
    NSString* tma_path = [[NSBundle mainBundle] pathForResource:@"tiny_marbles" ofType:@"png"];
    if (!tma_path)
      @throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Unable to find tiny_marbles.png." userInfo:nil];

    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)[NSURL fileURLWithPath : tma_path], NULL);
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);

    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);

    void* data = malloc(width * height * 4);
    CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(data, width, height, 8, width * 4, color_space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);

    CFRelease(context);
    CFRelease(color_space);
    CFRelease(image);

    // get the load context and lock it
    CGLContextObj cgl_ctx = [g_worldView loadContext];
    CGLLockContext(cgl_ctx);

    // create, bind and configure the tiny marble texture atlas
    GLuint texture;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, texture);
    glReportError();
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glReportError();
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glReportError();
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glReportError();
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glReportError();

    // disable client storage for this texture unpack operation (we just keep the texture alive in GL for ever)
    GLenum client_storage = [RXGetContextState(cgl_ctx) setUnpackClientStorage:GL_FALSE];

    // unpack the texture
    glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, 16, 16, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glReportError();
    glTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, 0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, data);
    glReportError();

    // restore client storage
    [RXGetContextState(cgl_ctx) setUnpackClientStorage:client_storage];

    // synchronize the new texture object with the rendering context by flushing
    glFlush();

    CGLUnlockContext(cgl_ctx);
    free(data);

    tiny_marble_atlas = [[RXTexture alloc] initWithID:texture target:GL_TEXTURE_RECTANGLE_ARB size:RXSizeMake(width, height) deleteWhenDone:YES];
  }

  RXGameState* gs = [g_world gameState];
  uint32_t waffle = [gs unsigned32ForKey:@"twaffle"];
  [self _drawTinyMarbleWithPosition:[gs unsigned32ForKey:@"tred"] index:0 waffle:waffle];
  [self _drawTinyMarbleWithPosition:[gs unsigned32ForKey:@"torange"] index:1 waffle:waffle];
  [self _drawTinyMarbleWithPosition:[gs unsigned32ForKey:@"tyellow"] index:2 waffle:waffle];
  [self _drawTinyMarbleWithPosition:[gs unsigned32ForKey:@"tgreen"] index:3 waffle:waffle];
  [self _drawTinyMarbleWithPosition:[gs unsigned32ForKey:@"tblue"] index:4 waffle:waffle];
  [self _drawTinyMarbleWithPosition:[gs unsigned32ForKey:@"tviolet"] index:5 waffle:waffle];
}

- (void)_initializeMarbleHotspotWithVariable:(NSString*)marble_var initialRectPointer:(rx_core_rect_t*)initial_rect_ptr
{
  RXGameState* gs = [g_world gameState];
  NSMapTable* hotspots_map = [_card hotspotsNameMap];

  RXHotspot* hotspot = (RXHotspot*)NSMapGet(hotspots_map, marble_var);
  *initial_rect_ptr = [hotspot coreFrame];
  uint32_t marble_pos = [gs unsigned32ForKey:marble_var];
  if (marble_pos) {
    uint32_t marble_x = (marble_pos >> 16) - 1;
    uint32_t marble_y = (marble_pos & 0xFFFF) - 1;

    rx_core_rect_t core_position;
    core_position.left = marble_offset_matrix[0][marble_x / 5] + marble_size * (marble_x % 5);
    core_position.right = core_position.left + marble_size;
    core_position.top = marble_offset_matrix[1][marble_y / 5] + marble_size * (marble_y % 5);
    core_position.bottom = core_position.top + marble_size;
    [hotspot setCoreFrame:core_position];
  }
}

DEFINE_COMMAND(xt7800_setup)
{
  // initialize the marble bitmap IDs
  NSDictionary* marble_map = [[g_world extraBitmapsDescriptor] objectForKey:@"Marbles"];
  blue_marble_tBMP = [[marble_map objectForKey:@"Blue"] unsignedShortValue];
  green_marble_tBMP = [[marble_map objectForKey:@"Green"] unsignedShortValue];
  orange_marble_tBMP = [[marble_map objectForKey:@"Orange"] unsignedShortValue];
  violet_marble_tBMP = [[marble_map objectForKey:@"Violet"] unsignedShortValue];
  red_marble_tBMP = [[marble_map objectForKey:@"Red"] unsignedShortValue];
  yellow_marble_tBMP = [[marble_map objectForKey:@"Yellow"] unsignedShortValue];

  // initialize the initial rects and set the hotspot's core rect to the marble's position
  [self _initializeMarbleHotspotWithVariable:@"tblue" initialRectPointer:&blue_marble_initial_rect];
  [self _initializeMarbleHotspotWithVariable:@"tgreen" initialRectPointer:&green_marble_initial_rect];
  [self _initializeMarbleHotspotWithVariable:@"torange" initialRectPointer:&orange_marble_initial_rect];
  [self _initializeMarbleHotspotWithVariable:@"tviolet" initialRectPointer:&violet_marble_initial_rect];
  [self _initializeMarbleHotspotWithVariable:@"tred" initialRectPointer:&red_marble_initial_rect];
  [self _initializeMarbleHotspotWithVariable:@"tyellow" initialRectPointer:&yellow_marble_initial_rect];
}

- (void)_drawMarbleWithVariable:(NSString*)marble_var
                     marbleEnum:(rx_fire_marble_t)marble
                       bitmapID:(uint16_t)bitmap_id
                   activeMarble:(rx_fire_marble_t)active_marble
{
  if (active_marble == marble)
    return;

  RXHotspot* hotspot = (RXHotspot*)NSMapGet([_card hotspotsNameMap], marble_var);
  rx_core_rect_t hotspot_rect = [hotspot coreFrame];
  hotspot_rect.left += 3;
  hotspot_rect.top += 3;
  hotspot_rect.right += 3;
  hotspot_rect.bottom += 3;

  NSRect display_rect = RXMakeCompositeDisplayRectFromCoreRect(hotspot_rect);
  [self _drawPictureWithID:bitmap_id
                   archive:[[RXArchiveManager sharedArchiveManager] extrasArchive:NULL]
               displayRect:display_rect
              samplingRect:NSMakeRect(0.0f, 0.0f, 0.0f, 0.0f)];
}

DEFINE_COMMAND(xdrawmarbles)
{
  RXGameState* gs = [g_world gameState];
  rx_fire_marble_t active_marble = (rx_fire_marble_t)[gs unsigned32ForKey : @"themarble"];

  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1);
  [self _drawMarbleWithVariable:@"tblue" marbleEnum:BLUE_MARBLE bitmapID:blue_marble_tBMP activeMarble:active_marble];
  [self _drawMarbleWithVariable:@"tgreen" marbleEnum:GREEN_MARBLE bitmapID:green_marble_tBMP activeMarble:active_marble];
  [self _drawMarbleWithVariable:@"torange" marbleEnum:ORANGE_MARBLE bitmapID:orange_marble_tBMP activeMarble:active_marble];
  [self _drawMarbleWithVariable:@"tviolet" marbleEnum:PURPLE_MARBLE bitmapID:violet_marble_tBMP activeMarble:active_marble];
  [self _drawMarbleWithVariable:@"tred" marbleEnum:RED_MARBLE bitmapID:red_marble_tBMP activeMarble:active_marble];
  [self _drawMarbleWithVariable:@"tyellow" marbleEnum:YELLOW_MARBLE bitmapID:yellow_marble_tBMP activeMarble:active_marble];
}

DEFINE_COMMAND(xtakeit)
{
  // themarble + t<color> variables probably should be used to keep track of state
  RXGameState* gs = [g_world gameState];

  // update themarble based on which marble hotspot we're in and set the marble position variable we'll be updating
  NSString* marble_var;
  rx_core_rect_t initial_rect;
  if ([[_current_hotspot name] isEqualToString:@"tblue"]) {
    [gs setUnsigned32:BLUE_MARBLE forKey:@"themarble"];
    marble_var = @"tblue";
    initial_rect = blue_marble_initial_rect;
  } else if ([[_current_hotspot name] isEqualToString:@"tgreen"]) {
    [gs setUnsigned32:GREEN_MARBLE forKey:@"themarble"];
    marble_var = @"tgreen";
    initial_rect = green_marble_initial_rect;
  } else if ([[_current_hotspot name] isEqualToString:@"torange"]) {
    [gs setUnsigned32:ORANGE_MARBLE forKey:@"themarble"];
    marble_var = @"torange";
    initial_rect = orange_marble_initial_rect;
  } else if ([[_current_hotspot name] isEqualToString:@"tviolet"]) {
    [gs setUnsigned32:PURPLE_MARBLE forKey:@"themarble"];
    marble_var = @"tviolet";
    initial_rect = violet_marble_initial_rect;
  } else if ([[_current_hotspot name] isEqualToString:@"tred"]) {
    [gs setUnsigned32:RED_MARBLE forKey:@"themarble"];
    marble_var = @"tred";
    initial_rect = red_marble_initial_rect;
  } else if ([[_current_hotspot name] isEqualToString:@"tyellow"]) {
    [gs setUnsigned32:YELLOW_MARBLE forKey:@"themarble"];
    marble_var = @"tyellow";
    initial_rect = yellow_marble_initial_rect;
  } else
    abort();

  // draw the marbles to reflect the new state
  DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);

  // track the mouse until the mouse button is released
  NSRect mouse_vector = [controller mouseVector];
  while (isfinite(mouse_vector.size.width)) {
    mouse_vector = [controller mouseVector];
    usleep(kRunloopPeriodMicroseconds);
  }

  // update the marble's position
  rx_core_rect_t core_position = RXTransformRectWorldToCore(mouse_vector);
#if defined(DEBUG)
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@core position of mouse is <%u, %u>", logPrefix, core_position.left, core_position.top);
#endif

  NSRect grid_rect =
      NSMakeRect(marble_offset_matrix[0][0], marble_offset_matrix[1][0], marble_offset_matrix[0][4] + marble_size * 5 - marble_offset_matrix[0][0],
                 marble_offset_matrix[1][4] + marble_size * 5 - marble_offset_matrix[1][0]);
  NSPoint core_rect_ns = NSMakePoint(core_position.left, core_position.top);

  // new marble position; UINT32_MAX indicates "invalid" and will cause the marble to reset to its initial position
  uint32_t marble_pos;
  uint32_t new_marble_pos = UINT32_MAX;
  uint32_t marble_x = UINT32_MAX;
  uint32_t marble_y = UINT32_MAX;

  if (NSMouseInRect(core_rect_ns, grid_rect, NO)) {
    // we're inside the grid, determine on which cell

    if (core_position.left < marble_offset_matrix[0][0] + 5 * marble_size)
      marble_x = (core_position.left - marble_offset_matrix[0][0]) / marble_size;
    else if (core_position.left < marble_offset_matrix[0][1] + 5 * marble_size)
      marble_x = 5 + (core_position.left - marble_offset_matrix[0][1]) / marble_size;
    else if (core_position.left < marble_offset_matrix[0][2] + 5 * marble_size)
      marble_x = 10 + (core_position.left - marble_offset_matrix[0][2]) / marble_size;
    else if (core_position.left < marble_offset_matrix[0][3] + 5 * marble_size)
      marble_x = 15 + (core_position.left - marble_offset_matrix[0][3]) / marble_size;
    else if (core_position.left < marble_offset_matrix[0][4] + 5 * marble_size)
      marble_x = 20 + (core_position.left - marble_offset_matrix[0][4]) / marble_size;

    if (core_position.top < marble_offset_matrix[1][0] + 5 * marble_size)
      marble_y = (core_position.top - marble_offset_matrix[1][0]) / marble_size;
    else if (core_position.top < marble_offset_matrix[1][1] + 5 * marble_size)
      marble_y = 5 + (core_position.top - marble_offset_matrix[1][1]) / marble_size;
    else if (core_position.top < marble_offset_matrix[1][2] + 5 * marble_size)
      marble_y = 10 + (core_position.top - marble_offset_matrix[1][2]) / marble_size;
    else if (core_position.top < marble_offset_matrix[1][3] + 5 * marble_size)
      marble_y = 15 + (core_position.top - marble_offset_matrix[1][3]) / marble_size;
    else if (core_position.top < marble_offset_matrix[1][4] + 5 * marble_size)
      marble_y = 20 + (core_position.top - marble_offset_matrix[1][4]) / marble_size;

    if (marble_x != UINT32_MAX && marble_y != UINT32_MAX) {
      // store the marble position using a 1-based coordinate system to reserve 0 as the "receptacle"
      new_marble_pos = (marble_x + 1) << 16 | (marble_y + 1);

      // check if a marble is already there; if so, reset the marble to its previous position
      marble_pos = [gs unsigned32ForKey:@"tblue"];
      if (marble_pos == new_marble_pos && ![marble_var isEqualToString:@"tblue"])
        new_marble_pos = [gs unsigned32ForKey:marble_var];
      else {
        marble_pos = [gs unsigned32ForKey:@"tgreen"];
        if (marble_pos == new_marble_pos && ![marble_var isEqualToString:@"tgreen"])
          new_marble_pos = [gs unsigned32ForKey:marble_var];
        else {
          marble_pos = [gs unsigned32ForKey:@"torange"];
          if (marble_pos == new_marble_pos && ![marble_var isEqualToString:@"torange"])
            new_marble_pos = [gs unsigned32ForKey:marble_var];
          else {
            marble_pos = [gs unsigned32ForKey:@"tviolet"];
            if (marble_pos == new_marble_pos && ![marble_var isEqualToString:@"tviolet"])
              new_marble_pos = [gs unsigned32ForKey:marble_var];
            else {
              marble_pos = [gs unsigned32ForKey:@"tred"];
              if (marble_pos == new_marble_pos && ![marble_var isEqualToString:@"tred"])
                new_marble_pos = [gs unsigned32ForKey:marble_var];
              else {
                marble_pos = [gs unsigned32ForKey:@"tyellow"];
                if (marble_pos == new_marble_pos && ![marble_var isEqualToString:@"tyellow"])
                  new_marble_pos = [gs unsigned32ForKey:marble_var];
              }
            }
          }
        }
      }
    } else
      new_marble_pos = [gs unsigned32ForKey:marble_var];
  }

  // update the marble's position by moving its hotspot
  RXHotspot* hotspot = (RXHotspot*)NSMapGet([_card hotspotsNameMap], marble_var);
  if (new_marble_pos == UINT32_MAX) {
    // the marble was dropped somewhere outside the grid;
    // set the marble variable to 0 to indicate the marble is in its receptacle
    [gs setUnsigned32:0 forKey:marble_var];

    // reset the marble hotspot's core frame
    [hotspot setCoreFrame:initial_rect];
  } else {
    // set the new marble's position
    [gs setUnsigned32:new_marble_pos forKey:marble_var];

    // update the convenience x and y position variables because new_marble_pos may have been changed
    marble_x = (new_marble_pos >> 16) - 1;
    marble_y = (new_marble_pos & 0xFFFF) - 1;

    // move the marble's hotspot to the new base location
    core_position.left = marble_offset_matrix[0][marble_x / 5] + marble_size * (marble_x % 5);
    core_position.right = core_position.left + marble_size;
    core_position.top = marble_offset_matrix[1][marble_y / 5] + marble_size * (marble_y % 5);
    core_position.bottom = core_position.top + marble_size;
    [hotspot setCoreFrame:core_position];
  }

  // we are no longer dragging a marble
  [gs setUnsigned32:0 forKey:@"themarble"];

  // draw the marbles to reflect the new state
  DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
}

DEFINE_COMMAND(xt7500_checkmarbles)
{
  RXGameState* gs = [g_world gameState];
  uint32_t marble_pos;

  // check if the marble configuration is correct
  BOOL correct_configuration = NO;
  marble_pos = [gs unsigned32ForKey:@"tblue"];
  if (marble_pos == (22 << 16 | 1)) {
    marble_pos = [gs unsigned32ForKey:@"tgreen"];
    if (marble_pos == (16 << 16 | 1)) {
      marble_pos = [gs unsigned32ForKey:@"torange"];
      if (marble_pos == (6 << 16 | 22)) {
        marble_pos = [gs unsigned32ForKey:@"tviolet"];
        if (marble_pos == (2 << 16 | 4)) {
          marble_pos = [gs unsigned32ForKey:@"tred"];
          if (marble_pos == (9 << 16 | 17)) {
            marble_pos = [gs unsigned32ForKey:@"tyellow"];
            if (marble_pos == 0) {
              correct_configuration = YES;
            }
          }
        }
      }
    }
  }

  if (correct_configuration) {
    [gs setUnsigned32:1 forKey:@"apower"];

    // the correct marble configuration resets all the marbles to their initial position
    [gs setUnsigned32:0 forKey:@"tblue"];
    [gs setUnsigned32:0 forKey:@"tgreen"];
    [gs setUnsigned32:0 forKey:@"torange"];
    [gs setUnsigned32:0 forKey:@"tviolet"];
    [gs setUnsigned32:0 forKey:@"tred"];
    [gs setUnsigned32:0 forKey:@"tyellow"];
  } else
    [gs setUnsigned32:0 forKey:@"apower"];
}

#pragma mark -
#pragma mark gspit scribe

DEFINE_COMMAND(xgwt200_scribetime) { [[g_world gameState] setUnsigned64:(uint64_t)(CFAbsoluteTimeGetCurrent() * 1000)forKey:@"gScribeTime"]; }

DEFINE_COMMAND(xgwt900_scribe)
{
  RXGameState* gs = [g_world gameState];
  uint64_t scribe_time = [gs unsigned64ForKey:@"gScribeTime"];
  uint32_t scribe = [gs unsigned32ForKey:@"gScribe"];
  if (scribe == 1 && (uint64_t)(CFAbsoluteTimeGetCurrent() * 1000) > scribe_time + 40000)
    [gs setUnsigned32:2 forKey:@"gScribe"];
}

#pragma mark -
#pragma mark gspit left viewer

static uint16_t const prison_activity_movies[3][8] = {{9, 10, 19, 19, 21, 21}, {18, 20, 22}, {11, 11, 12, 17, 17, 17, 17, 23}};

- (void)_playRandomPrisonActivityMovie:(NSTimer*)timer
{
  RXGameState* gs = [g_world gameState];
  uint32_t cath_state = [gs unsigned32ForKey:@"gCathState"];

  uint16_t prison_mlst;
  if (cath_state == 1)
    prison_mlst = prison_activity_movies[0][rx_rnd_range(0, 5)];
  else if (cath_state == 2)
    prison_mlst = prison_activity_movies[1][rx_rnd_range(0, 2)];
  else if (cath_state == 3)
    prison_mlst = prison_activity_movies[2][rx_rnd_range(0, 7)];
  else
    abort();

  // update catherine's state based on which movie we selected
  if (prison_mlst == 10 || prison_mlst == 17 || prison_mlst == 18 || prison_mlst == 20)
    cath_state = 1;
  else if (prison_mlst == 19 || prison_mlst == 21 || prison_mlst == 23)
    cath_state = 2;
  else
    cath_state = 3;
  [gs setUnsigned32:cath_state forKey:@"gCathState"];

  // play the movie
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)(uintptr_t)30);
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_MLST_AND_START, prison_mlst);
  if (movie)
    [controller disableMovie:movie];

  // schedule the next prison activity movie
  NSTimeInterval delay;
  movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)(uintptr_t)30);
  QTGetTimeInterval([movie duration], &delay);
  delay += rx_rnd_range_normal_clamped(30, 15);

  [event_timer invalidate];
  event_timer = [NSTimer scheduledTimerWithTimeInterval:delay target:self selector:@selector(_playRandomPrisonActivityMovie:) userInfo:nil repeats:NO];
}

DEFINE_COMMAND(xglview_prisonon)
{
  RXGameState* gs = [g_world gameState];

  // set gLView to indicate the left viewer is on
  [gs setUnsigned32:1 forKey:@"gLView"];

  // MLST 8 to 23 (16 movies) are the prison activity movies; pick one
  uint16_t prison_mlst = rx_rnd_range(8, 23);

  // now need to select the correct viewer turn on movie and catherine state based on the selection above
  uintptr_t turnon_code;
  uint16_t cath_state;
  if (prison_mlst == 8 || prison_mlst == 10 || prison_mlst == 13 || (prison_mlst >= 16 && prison_mlst <= 18) || prison_mlst == 20) {
    turnon_code = 4;
    cath_state = 1;
  } else if (prison_mlst == 19 || prison_mlst == 21 || prison_mlst == 23) {
    turnon_code = 4;
    cath_state = 2;
  } else if (prison_mlst == 9 || prison_mlst == 11 || prison_mlst == 12 || prison_mlst == 22) {
    turnon_code = 4;
    cath_state = 3;
  } else if (prison_mlst == 14) {
    turnon_code = 6;
    cath_state = 2;
  } else if (prison_mlst == 15) {
    turnon_code = 7;
    cath_state = 1;
  } else
    abort();

  // set catherine's current state
  [gs setUnsigned32:cath_state forKey:@"gCathState"];

  // disable screen updates
  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);

  // activate the viewer on PLST
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 8);

  // play the appropriate viewer turn on movie
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, turnon_code);

  // if the selected movie is one where catherine is visible at the start, we need to play it now
  if (prison_mlst == 8 || (prison_mlst >= 13 && prison_mlst <= 16))
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_MLST_AND_START, prison_mlst);
  else
    NSMapRemove(code_movie_map, (const void*)(uintptr_t)30);

  // enable screen updates
  DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);

  // schedule the next prison activity movie
  uintptr_t k = 30;
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)k);
  NSTimeInterval delay;
  if (movie) {
    QTGetTimeInterval([movie duration], &delay);
    delay += rx_rnd_range_normal_clamped(45, 15);
  } else {
    delay = rx_rnd_range_normal_clamped(13, 3);
  }

  [event_timer invalidate];
  event_timer = [NSTimer scheduledTimerWithTimeInterval:delay target:self selector:@selector(_playRandomPrisonActivityMovie:) userInfo:nil repeats:NO];
}

DEFINE_COMMAND(xglview_prisonoff)
{
  // set gLView to indicate the viewer is off
  [[g_world gameState] setUnsigned32:0 forKey:@"gLView"];

  // invalidate the event timer
  [event_timer invalidate];
  event_timer = nil;

  // disable screen updates, activate PLST 1 (viewer off background), play
  // movie 5 (viewer turn off), enable screen updates and disable all movies
  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1);
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 5);
  DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_ALL_MOVIES);
}

DEFINE_COMMAND(xglview_villageon)
{
  RXGameState* gs = [g_world gameState];

  // set gLView to indicate the right viewer is on
  [gs setUnsigned32:2 forKey:@"gLView"];

  // activate the correct village viewer picture
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 2 + [gs unsignedShortForKey:@"gLViewPos"]);
}

DEFINE_COMMAND(xglview_villageoff)
{
  // set gLView to indicate the viewer is off
  [[g_world gameState] setUnsigned32:0 forKey:@"gLView"];

  // activate the viewer off picture
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1);
}

static int64_t const left_viewer_spin_timevals[] = {0LL, 816LL, 1617LL, 2416LL, 3216LL, 4016LL, 4816LL, 5616LL, 6416LL, 7216LL, 8016LL, 8816LL};

- (void)_configureLeftViewerSpinMovie
{
  RXGameState* gs = [g_world gameState];
  NSString* hn = [_current_hotspot name];

  // determine the new left viewer position based on the hotspot name
  uint32_t old_pos = [gs unsigned32ForKey:@"gLViewPos"];
  uint32_t new_pos = old_pos + [[hn substringFromIndex:[hn length] - 1] intValue];

  // determine the playback selection for the viewer spin movie
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)(uintptr_t)1);
  QTTime duration = [movie duration];

  QTTime start_time = QTMakeTime(left_viewer_spin_timevals[old_pos], duration.timeScale);
  QTTimeRange movie_range = QTMakeTimeRange(start_time, QTMakeTime(left_viewer_spin_timevals[new_pos] - start_time.timeValue, duration.timeScale));
  [movie setPlaybackSelection:movie_range];

  // update the position variable
  [gs setUnsigned32:new_pos % 6 forKey:@"gLViewPos"];
}

DEFINE_COMMAND(xglviewer)
{
  RXGameState* gs = [g_world gameState];

  // configure the viewer spin movie playback selection and play it
  [self performSelectorOnMainThread:@selector(_configureLeftViewerSpinMovie) withObject:nil waitUntilDone:YES];
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 1);

  // activate the appropriate PLST and disable the viewer spin movie
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 2 + [gs unsigned32ForKey:@"gLViewPos"]);
  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 1);
}

#pragma mark -
#pragma mark gspit right viewer

static int64_t const right_viewer_spin_timevals[] = {0LL, 816LL, 1617LL, 2416LL, 3216LL, 4016LL, 4816LL, 5616LL, 6416LL, 7216LL, 8016LL, 8816LL};

- (void)_configureRightViewerSpinMovie
{
  RXGameState* gs = [g_world gameState];
  NSString* hn = [_current_hotspot name];

  // determine the new right viewer position based on the hotspot name
  uint32_t old_pos = [gs unsigned32ForKey:@"gRViewPos"];
  uint32_t new_pos = old_pos + [[hn substringFromIndex:[hn length] - 1] intValue];

  // determine the playback selection for the viewer spin movie
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)(uintptr_t)1);
  QTTime duration = [movie duration];

  QTTime start_time = QTMakeTime(right_viewer_spin_timevals[old_pos], duration.timeScale);
  QTTimeRange movie_range = QTMakeTimeRange(start_time, QTMakeTime(right_viewer_spin_timevals[new_pos] - start_time.timeValue, duration.timeScale));
  [movie setPlaybackSelection:movie_range];

  // update the position variable
  [gs setUnsigned32:new_pos % 6 forKey:@"gRViewPos"];
}

DEFINE_COMMAND(xgrviewer)
{
  RXGameState* gs = [g_world gameState];

  // if the viewer light is active, we need to turn it off first
  uint32_t viewer_light = [gs unsigned32ForKey:@"gRView"];
  if (viewer_light == 1) {
    [gs setUnsigned32:0 forKey:@"gRView"];

    uint16_t button_up_sound = [_card dataSoundIDWithName:@"gScpBtnUp"];
    [self _playDataSoundWithID:button_up_sound gain:1.0f duration:NULL];

    DISPATCH_COMMAND0(RX_COMMAND_REFRESH);

    // sleep for a little bit less than a second (the duration of the button up sound)
    usleep(0.2 * 1E6);
  }

  // configure the viewer spin movie playback selection and play it
  [self performSelectorOnMainThread:@selector(_configureRightViewerSpinMovie) withObject:nil waitUntilDone:YES];
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 1);

  // refresh the card
  DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
}

- (void)_playWharkSolo:(NSTimer*)timer
{
  RXGameState* gs = [g_world gameState];

  // if the whark got angry at us, or there is no light turned on, don't play
  // a solo and don't schedule another one; we make an exception if
  // played_whark_solo is NO (so that the player hears at least one even if
  // he or she toggled the light back off)
  BOOL play_solo = [gs unsigned32ForKey:@"gWhark"] < 5 && [gs unsigned32ForKey:@"gRView"];
  if (!play_solo && played_one_whark_solo) {
    [event_timer invalidate];
    event_timer = nil;
    return;
  }

  // get a random solo index (there's 9 of them)
  uint32_t whark_solo = rx_rnd_range(1, 9);

  // play the solo
  uint16_t solo_sound = [whark_solo_card dataSoundIDWithName:[NSString stringWithFormat:@"gWharkSolo%d", whark_solo]];
  [self _playDataSoundWithID:solo_sound gain:1.0f duration:NULL];

  if (play_solo)
    // schedule the next one within the next 5 minutes but no sooner than in 2 minutes
    event_timer = [NSTimer scheduledTimerWithTimeInterval:120 + rx_rnd_range(0, 180) target:self selector:@selector(_playWharkSolo:) userInfo:nil repeats:NO];
  else {
    // we got here if played_whark_solo was NO (so we forced the solo to
    // play), but play_solo is NO, meaning we should not schedule another
    // solo; invalidate the event timer and set it to nil (setting it to
    // nil will allow xgwharksnd to re-schedule solos again)
    [event_timer invalidate];
    event_timer = nil;
  }

  // we have now played a solo
  played_one_whark_solo = YES;
  [gs setUnsigned32:1 forKey:@"played_one_whark_solo"];
}

DEFINE_COMMAND(xgwharksnd)
{
  // cache an un-loaded copy of the whark solo card so we can load the solos later on other cards
  whark_solo_card = [[RXCard alloc] initWithCardDescriptor:[_card descriptor]];

  // play a solo within the next 5 seconds if we've never played one before
  // otherwise within the next 5 minutes but no sooner than in 2 minutes;
  // only do the above if the event timer is nil, otherwise don't disturb it
  // (e.g. if the player toggles the light rapidly, don't keep re-scheduling
  // the next solo)
  if (event_timer)
    return;

  if (!played_one_whark_solo)
    event_timer = [NSTimer scheduledTimerWithTimeInterval:rx_rnd_range(0, 5) target:self selector:@selector(_playWharkSolo:) userInfo:nil repeats:NO];
  else
    event_timer = [NSTimer scheduledTimerWithTimeInterval:120 + rx_rnd_range(0, 180) target:self selector:@selector(_playWharkSolo:) userInfo:nil repeats:NO];
}

DEFINE_COMMAND(xgplaywhark)
{
  RXGameState* gs = [g_world gameState];

  uint32_t whark_visits = [gs unsigned32ForKey:@"gWhark"];
  uint64_t whark_state = [gs unsigned64ForKey:@"gWharkTime"];

  // if gWharkTime is not 1, we don't do anything
  if (whark_state != 1)
    return;

  // don't trigger a Whark event unless the red light has been toggled off and back on by setting gWharkTime back to 0
  [gs setUnsigned32:0 forKey:@"gWharkTime"];

  // count the number of times the red light has been lit / the whark has come
  whark_visits++;
  if (whark_visits > 5)
    whark_visits = 5;
  [gs setUnsigned32:whark_visits forKey:@"gWhark"];

  // determine which movie to play based on the visit count
  uint16_t mlst_index;
  if (whark_visits == 1)
    mlst_index = 3; // first whark movie, where we get a good look at it
  else if (whark_visits == 2)
    mlst_index = rx_rnd_range(4, 5); // random 4 or 5
  else if (whark_visits == 3)
    mlst_index = rx_rnd_range(6, 7); // random 6 or 7
  else if (whark_visits == 4)
    mlst_index = 8; // he's pissed, hope that glass doesn't break
  else
    return;

  // and play the movie; they all use code 31
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_MLST_AND_START, mlst_index);
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 31);
  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 31);
}

#pragma mark -
#pragma mark gspit pools

DEFINE_COMMAND(xgplateau3160_dopools)
{
  // if another pool is already active, we need to play it's disable movie
  uint32_t pool_button = [[g_world gameState] unsigned32ForKey:@"glkbtns"];
  switch (pool_button) {
  case 1:
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);
    break;
  case 2:
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 4);
    break;
  case 3:
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 6);
    break;
  case 4:
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 8);
    break;
  case 5:
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 10);
    break;
  default:
    break;
  }
}

#pragma mark -
#pragma mark village trapeze

DEFINE_COMMAND(xvga1300_carriage)
{
  RXTransition* transition;

  // first play the handle movie (code 1)
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 1);
  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 1);

  // in a transaction, queue a slide up transition and enable picture 7
  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);

  // we need to disable screen update programs to avoid painting the floor
  _disable_screen_update_programs = YES;

  // we need to disable the water effect while we're looking up
  [controller disableWaterSpecialEffect];

  transition = [[RXTransition alloc] initWithCode:15 region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
  [controller queueTransition:transition];
  [transition release];

  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 7);
  DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);

  // re-enable screen update programs
  _disable_screen_update_programs = NO;

  // play the trapeze coming down from above movie (code 4)
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 4);
  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 4);

  // in a transaction, queue a slide down transition and enable picture 1
  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);

  transition = [[RXTransition alloc] initWithCode:14 region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
  [controller queueTransition:transition];
  [transition release];

  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1);
  DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);

  // re-enable the water special effect; we have to do this after the screen
  // update otherwise the transition will be wrong
  [controller enableWaterSpecialEffect];

  // play the trapeze coming down movie (code 2)
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);

  // show the cursor again (it was hidden by the play movie blocking commands)
  [self _showMouseCursor];

  // if the gallows floor is open, the player can't hop on the trapeze and we
  // just sleep the thread for 5 seconds then have the trapeze go up
  if ([[g_world gameState] unsigned32ForKey:@"jGallows"]) {
    // wait 5 seconds
    usleep(5 * 1E6);

    // play the trapeze going up movie (code 3)
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE, 3);
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 2);
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 3);
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 3);

    // refresh the card
    DISPATCH_COMMAND0(RX_COMMAND_REFRESH);

    // all done
    return;
  }

  // run the run loop and wait for a mouse down event within the next
  // 5 seconds
  CFAbsoluteTime trapeze_window_end = CFAbsoluteTimeGetCurrent() + 5.0;
  rx_event_t mouse_down_event = [controller lastMouseDownEvent];
  BOOL mouse_was_pressed = NO;
  while (1) {
    // have we passed the trapeze window?
    if (trapeze_window_end < CFAbsoluteTimeGetCurrent())
      break;

    // if the mouse has been pressed, update the mouse down event
    rx_event_t event = [controller lastMouseDownEvent];
    if (event.timestamp > mouse_down_event.timestamp) {
      mouse_down_event = event;

      // check where the mouse was pressed, and if it is inside the
      // trapeze region, set mouse_was_pressed to YES and exit the loop
      rx_core_rect_t core_pos = RXTransformRectWorldToCore(NSMakeRect(mouse_down_event.location.x, mouse_down_event.location.y, 0.0f, 0.0f));
      NSPoint core_pos_ns = NSMakePoint(core_pos.left, core_pos.top);
      if (NSMouseInRect(core_pos_ns, trapeze_rect, NO)) {
        mouse_was_pressed = YES;
        break;
      }
    }

    usleep(kRunloopPeriodMicroseconds);
  }

  // if the player did not click on the trapeze within the alloted time, have
  // the trapeze go back up
  if (!mouse_was_pressed) {
    // play the trapeze going up movie (code 3)
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE, 3);
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 2);
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 3);
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 3);

    // refresh the card
    DISPATCH_COMMAND0(RX_COMMAND_REFRESH);

    // all done
    return;
  }

  // hide the cursor (if it is not already hidden)
  [self _hideMouseCursor];

  // schedule a forward transition
  transition = [[RXTransition alloc] initWithCode:16 region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
  [controller queueTransition:transition];
  [transition release];

  // go to card RMAP 101709
  uint16_t card_id = [[[_card descriptor] parent] cardIDFromRMAPCode:101709];
  DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, card_id);

  // schedule a transition with code 12 (from left, push new and old)
  transition = [[RXTransition alloc] initWithCode:12 region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
  [controller queueTransition:transition];
  [transition release];

  // go to card RMAP 101045
  card_id = [[[_card descriptor] parent] cardIDFromRMAPCode:101045];
  DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, card_id);

  // play movie with code 1 (going up movie)
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE, 1);

  // wait 7 seconds before activating the "upper village" ambience
  usleep(7 * 1E6);

  // activate SLST 2 (upper village ambience)
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_SLST, 2);

  // wait the movie to end
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 1);

  // go to card RMAP 94567
  card_id = [[[_card descriptor] parent] cardIDFromRMAPCode:94567];
  DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, card_id);
}

#pragma mark -
#pragma mark gspit topology viewer

static rx_point_t const pin_control_grid_origin = {279, 325};
static uint16_t const pin_id_counts[] = {5, 5, 12, 2, 6};
static uint16_t const pin_ids[5][12] = {{0, 1, 2, 6, 7}, {0, 11, 16, 21, 22}, {0, 12, 13, 14, 15, 17, 18, 19, 20, 23, 24, 25}, {0, 5}, {0, 3, 4, 8, 9, 10}};

static int16_t const pin_movie_codes[] = {1, 2, 1, 2, 1, 3, 4, 3, 4, 5, 1, 1, 2, 3, 4, 2, 5, 6, 7, 8, 3, 4, 9, 10, 11};

- (void)_configurePinMovieForRotation
{
  RXGameState* gs = [g_world gameState];

  // get the old (current) position, the new position and the current pin movie code
  int32_t old_pos = [gs unsigned32ForKey:@"gPinPos"];
  uintptr_t pin_movie_code = [gs unsigned32ForKey:@"gUpMoov"];

  // update the pin position variable
  if (old_pos == 4)
    [gs setUnsigned32:1 forKey:@"gPinPos"];
  else
    [gs setUnsigned32:old_pos + 1 forKey:@"gPinPos"];

  // configure the playback selection for the pin movie
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)pin_movie_code);
  if (!movie)
    return;

  QTTime start_time = QTMakeTime((old_pos - 1) * 1200, 600);
  QTTimeRange movie_range = QTMakeTimeRange(start_time, QTMakeTime(1215, 600));
  [movie setPlaybackSelection:movie_range];
}

- (void)_configurePinMovieForRaise
{
  RXGameState* gs = [g_world gameState];

  uintptr_t pin_movie_code = [gs unsigned32ForKey:@"gUpMoov"];
  uint32_t pin_pos = [gs unsigned32ForKey:@"gPinPos"];

  // configure the playback selection for the pin movie
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)pin_movie_code);
  if (!movie)
    return;

  QTTime start_time = QTMakeTime(9600 - pin_pos * 600 + 30, 600);
  QTTimeRange movie_range = QTMakeTimeRange(start_time, QTMakeTime(580 - 30, 600));
  [movie setPlaybackSelection:movie_range];
}

- (void)_configurePinMovieForLower
{
  RXGameState* gs = [g_world gameState];

  uintptr_t pin_movie_code = [gs unsigned32ForKey:@"gUpMoov"];
  uint32_t pin_pos = [gs unsigned32ForKey:@"gPinPos"];

  // configure the playback selection for the pin movie
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)pin_movie_code);
  if (!movie)
    return;

  QTTime start_time = QTMakeTime(4800 + (pin_pos - 1) * 600 + 30, 600);
  QTTimeRange movie_range = QTMakeTimeRange(start_time, QTMakeTime(580 - 30, 600));
  [movie setPlaybackSelection:movie_range];
}

- (void)_raiseTopographyPins:(uint16_t)pin_id
{
  RXGameState* gs = [g_world gameState];

  uint16_t new_pin_movie_code = pin_movie_codes[pin_id - 1];
  uint16_t old_pin_movie_code = [gs unsigned32ForKey:@"gUpMoov"];

  // set the new pin movie now, before we call _configurePinMovieForRaise
  // (so that the method works on the correct movie)
  [gs setUnsignedShort:new_pin_movie_code forKey:@"gUpMoov"];

  // configure the new pin movie for a raise
  [self performSelectorOnMainThread:@selector(_configurePinMovieForRaise) withObject:nil waitUntilDone:YES];

  // get the pin raise sound
  uint16_t pin_raise_sound = [_card dataSoundIDWithName:@"gPinsUp"];

  // play the pin raise sound and movie
  [self _playDataSoundWithID:pin_raise_sound gain:1.0f duration:NULL];
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, new_pin_movie_code);

  // disable the previous up movie (if it is different from the new movie code)
  if (old_pin_movie_code && old_pin_movie_code != new_pin_movie_code)
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, old_pin_movie_code);

  // set the current raised pin ID variable
  [gs setUnsignedShort:pin_id forKey:@"gPinUp"];
}

- (void)_lowerTopographyPins:(uint16_t)pin_id
{
  RXGameState* gs = [g_world gameState];

  uint16_t pin_movie_code = pin_movie_codes[pin_id - 1];

  // configure the new pin movie for lower
  [self performSelectorOnMainThread:@selector(_configurePinMovieForLower) withObject:nil waitUntilDone:YES];

  // get the pin lower sound
  uint16_t pin_lower_sound = [_card dataSoundIDWithName:@"gPinsDn"];

  // play the pin lower sound and movie
  [self _playDataSoundWithID:pin_lower_sound gain:1.0f duration:NULL];
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, pin_movie_code);

  // reset PinUp
  [gs setUnsignedShort:0 forKey:@"gPinUp"];
}

DEFINE_COMMAND(xgrotatepins)
{
  RXGameState* gs = [g_world gameState];

  // if no pins are raised, we do nothing
  if (![gs unsigned32ForKey:@"gPinUp"])
    return;

  // configure the raised pin movie for a rotation
  [self performSelectorOnMainThread:@selector(_configurePinMovieForRotation) withObject:nil waitUntilDone:YES];

  // get the raised pin movie
  uintptr_t pin_movie_code = [gs unsigned32ForKey:@"gUpMoov"];

  // get the pin rotation sound
  uint16_t pin_rotation_sound = [_card dataSoundIDWithName:@"gPinsRot"];

  // play the pin rotate sound and movie
  [self _playDataSoundWithID:pin_rotation_sound gain:1.0f duration:NULL];
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, pin_movie_code);
}

DEFINE_COMMAND(xgpincontrols)
{
  RXGameState* gs = [g_world gameState];

  NSPoint mouse_pos = [_current_hotspot event].location;
  rx_core_rect_t core_pos = RXTransformRectWorldToCore(NSMakeRect(mouse_pos.x, mouse_pos.y, 0.0f, 0.0f));

  // get the base index of the selected pin
  int16_t pin_x = (core_pos.left - pin_control_grid_origin.x) / 9.8;
  int16_t pin_y = (core_pos.top - pin_control_grid_origin.y) / 10.8;

  // based on the pin position (the rotational position), figure out the pin control grid position we hit
  uint32_t pin_pos = [gs unsigned32ForKey:@"gPinPos"];
  if (pin_pos == 1) {
    pin_x = 5 - pin_x;
    pin_y = (4 - pin_y) * 5;
  } else if (pin_pos == 2) {
    pin_x = (4 - pin_x) * 5;
    pin_y = 1 + pin_y;
  } else if (pin_pos == 3) {
    pin_x = 1 + pin_x;
    pin_y = pin_y * 5;
  } else if (pin_pos == 4) {
    pin_x = pin_x * 5;
    pin_y = 5 - pin_y;
  } else
    abort();

  uint32_t island_index = [gs unsigned32ForKey:@"gLkBtns"];
  uint16_t pin_id = pin_x + pin_y;
  uint16_t up_pin_id = [gs unsignedShortForKey:@"gPinUp"];

  // determine if we've hit a valid pin control by going over the pin IDs for the current island
  uint16_t const* islan_pin_ids = pin_ids[island_index - 1];
  uint16_t pin_count = pin_id_counts[island_index - 1];
  uint16_t pin_index = 0;
  for (; pin_index < pin_count; pin_index++) {
    if (islan_pin_ids[pin_index] == pin_id)
      break;
  }
  if (pin_index == pin_count)
    return;

  // if there are raised pins, lower them now
  if (up_pin_id)
    [self _lowerTopographyPins:up_pin_id];

  // if the selected pins are different than the (previously) raised pins, raise the selected pins
  if (pin_id != up_pin_id)
    [self _raiseTopographyPins:pin_id];
}

DEFINE_COMMAND(xgresetpins)
{
  RXGameState* gs = [g_world gameState];

  // if there are raised pins, lower them now
  uint16_t up_pin_id = [gs unsignedShortForKey:@"gPinUp"];
  if (up_pin_id)
    [self _lowerTopographyPins:up_pin_id];

  // we can reset the UpMoov to 0 now
  [gs setUnsignedShort:0 forKey:@"gUpMoov"];
}

#pragma mark -
#pragma mark frog trap

DEFINE_COMMAND(xbait)
{
  // set the cursor to the "bait" cursor
  [controller setMouseCursor:RX_CURSOR_BAIT];

  // track the mouse until the mouse button is released
  NSRect mouse_vector = [controller mouseVector];
  while (isfinite(mouse_vector.size.width)) {
    [controller setMouseCursor:RX_CURSOR_BAIT];
    mouse_vector = [controller mouseVector];

    usleep(kRunloopPeriodMicroseconds);
  }

  // did we drop the bait over the bait plate?
  RXHotspot* plate_hotspot = (RXHotspot*)NSMapGet([_card hotspotsNameMap], @"baitplate");
  release_assert(plate_hotspot);
  if (!NSMouseInRect(mouse_vector.origin, [plate_hotspot worldFrame], NO))
    return;

  // set bbait to 1
  [[g_world gameState] setUnsigned32:1 forKey:@"bbait"];

  // paint picture 4
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 4);

  // disable the bait (9) hotspot and enable the baitplate (16) hotspot
  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, 9);
  DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, 16);
}

DEFINE_COMMAND(xbaitplate)
{
  // paint picture 3 (no bait on the plate)
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 3);

  // set the cursor to the "bait" cursor
  [controller setMouseCursor:RX_CURSOR_BAIT];

  // track the mouse until the mouse button is released
  NSRect mouse_vector = [controller mouseVector];
  while (isfinite(mouse_vector.size.width)) {
    [controller setMouseCursor:RX_CURSOR_BAIT];
    mouse_vector = [controller mouseVector];

    usleep(kRunloopPeriodMicroseconds);
  }

  // did we drop the bait over the bait plate?
  RXHotspot* plate_hotspot = (RXHotspot*)NSMapGet([_card hotspotsNameMap], @"baitplate");
  release_assert(plate_hotspot);
  if (NSMouseInRect(mouse_vector.origin, [plate_hotspot worldFrame], NO)) {
    // set bbait to 1
    [[g_world gameState] setUnsigned32:1 forKey:@"bbait"];

    // paint picture 4 (bait on the plate)
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 4);

    // disable the bait (9) hotspot and enable the baitplate (16) hotspot
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, 9);
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, 16);
  } else {
    // set bbait to 0
    [[g_world gameState] setUnsigned32:0 forKey:@"bbait"];

    // enable the bait (9) hotspot and disable the baitplate (16) hotspot
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, 9);
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, 16);
  }
}

- (void)_catchFrog:(NSTimer*)timer
{
  [event_timer invalidate];
  event_timer = nil;

  // if we're no longer in the frog trap card, bail out
  if (![[[_card descriptor] simpleDescriptor] isEqual:frog_trap_scdesc])
    return;

  // dispatch xbcheckcatch with 1 (e.g. play the trap sound)
  rx_dispatch_external1(self, @"xbcheckcatch", 1);
}

DEFINE_COMMAND(xbsettrap)
{
  // compute a random catch delay - up to 1 minute, and no sooner than within 10 seconds
  NSTimeInterval catch_delay = 10 + rx_rnd_range(0, 50);

  // remember the frog trap card, because we need to abort the catch frog event if we've switched to a different card
  frog_trap_scdesc = [[[_card descriptor] simpleDescriptor] retain];

  // schedule the event timer
  [event_timer invalidate];
  event_timer = [NSTimer scheduledTimerWithTimeInterval:catch_delay target:self selector:@selector(_catchFrog:) userInfo:nil repeats:NO];

  // set the trap time to the catch delay in usecs
  [[g_world gameState] setUnsigned64:catch_delay * 1E6 forKey:@"bytramtime"];
}

DEFINE_COMMAND(xbcheckcatch)
{
  if (argc < 1)
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];

  RXGameState* gs = [g_world gameState];

  // if bytramtime is 0, we're too late (or the trap has been raised) and we just exit
  if ([gs unsigned64ForKey:@"bytramtime"] == 0)
    return;

  // reset the trap time to 0
  [[g_world gameState] setUnsigned64:0 forKey:@"bytramtime"];

  // increment bytram (the specific frog movie we'll play) and clamp to 3
  uint16_t frog_movie = [gs unsignedShortForKey:@"bytram"];
  frog_movie++;
  if (frog_movie > 3)
    frog_movie = 3;
  [[g_world gameState] setUnsignedShort:frog_movie forKey:@"bytram"];

  // set bytrapped to 1
  [[g_world gameState] setUnsigned32:1 forKey:@"bytrapped"];

  // set bbait to 0 (frog took the bait)
  [[g_world gameState] setUnsigned32:0 forKey:@"bbait"];

  // set bytrap to 0 (which indicates that the trap is down and closed)
  [[g_world gameState] setUnsigned32:0 forKey:@"bytrap"];

  // play the catch sound effect if argv[0] is 1
  if (argv[0]) {
    uint16_t trap_sound = [_card dataSoundIDWithName:@"bYTCaught"];
    [self _playDataSoundWithID:trap_sound gain:1.0f duration:NULL];
  }
}

DEFINE_COMMAND(xbfreeytram)
{
  // this is basically used to play a random frog movie based on bytram
  uint16_t frog_movie = [[g_world gameState] unsignedShortForKey:@"bytram"];
  uint16_t mlst_index;

  // pick a random MLST for the trap open with frog inside movie
  if (frog_movie == 1)
    mlst_index = 11;
  else if (frog_movie == 2)
    mlst_index = 12;
  else
    mlst_index = rx_rnd_range(13, 15);

  // activate the chosen MLST
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_MLST, mlst_index);

  // all the above movies have code 11, so play and wait on code 11
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 11);

  // each of the trap open with frog inside movie has a corresponding closeup movie at index + 5, so play that now;
  // those those closeup movies all have code 12
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_MLST, mlst_index + 5);
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 12);

  // paint picture 3 (no bait on the plate)
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 3);

  // disable all movies
  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_ALL_MOVIES);
}

#pragma mark -
#pragma mark telescope

static int64_t const telescope_raise_timevals[] = {0LL, 800LL, 1680LL, 2560LL, 3440LL, 4320LL};
static int64_t const telescope_lower_timevals[] = {4320LL, 3440LL, 2660LL, 1760LL, 880LL, 0LL};

- (void)_configureTelescopeRaiseMovie
{
  RXGameState* gs = [g_world gameState];

  // get the current telescope position
  uint32_t tele_position = [gs unsignedShortForKey:@"ttelescope"];

  // determine the playback selection for the telescope raise movie
  uintptr_t movie_code = ([gs unsignedShortForKey:@"ttelecover"] == 1) ? 4 : 5;
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)movie_code);
  QTTime duration = [movie duration];

  QTTime start_time = QTMakeTime(telescope_raise_timevals[tele_position - 1], duration.timeScale);
  QTTimeRange movie_range = QTMakeTimeRange(start_time, QTMakeTime(telescope_raise_timevals[tele_position] - start_time.timeValue + 7, duration.timeScale));
  [movie setPlaybackSelection:movie_range];

  // update the telescope position
  [gs setUnsigned32:tele_position + 1 forKey:@"ttelescope"];
}

- (void)_configureTelescopeLowerMovie
{
  RXGameState* gs = [g_world gameState];

  // get the current telescope position
  uint32_t tele_position = [gs unsignedShortForKey:@"ttelescope"];

  // determine the playback selection for the telescope lower movie
  uintptr_t movie_code = ([gs unsignedShortForKey:@"ttelecover"] == 1) ? 1 : 2;
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)movie_code);
  QTTime duration = [movie duration];

  QTTime start_time = QTMakeTime(telescope_lower_timevals[tele_position], duration.timeScale);
  QTTimeRange movie_range = QTMakeTimeRange(start_time, QTMakeTime(telescope_lower_timevals[tele_position - 1] - start_time.timeValue + 7, duration.timeScale));
  [movie setPlaybackSelection:movie_range];

  // update the telescope position
  [gs setUnsigned32:tele_position - 1 forKey:@"ttelescope"];
}

- (void)_playFissureEndgame
{
  RXGameState* gs = [g_world gameState];

  // there are 4 possible endings at the fissure
  // 1: Gehn trapped and Catherine freed
  // 2: Gehn trapped but Catherine still imprisoned
  // 3: Ghen free (and obviously Catherine still imprisoned)
  // 4: Trap book not recovered (which is the ending where Atrus does not link to Riven)

  uint16_t catherine_state = [gs unsignedShortForKey:@"pcage"];
  uint16_t gehn_state = [gs unsignedShortForKey:@"agehn"];
  uint16_t trap_book = [gs unsignedShortForKey:@"atrapbook"];

  uint16_t movie_mlst;
  if (catherine_state == 2)
    // catherine is free
    movie_mlst = 8;
  else if (gehn_state == 4)
    // gehn is trapped
    movie_mlst = 9;
  else if (trap_book == 1)
    // gehn is free, what have you done!
    movie_mlst = 10;
  else
    // lucky guess
    movie_mlst = 11;

  [self _endgameWithMLST:movie_mlst delay:5.];
}

DEFINE_COMMAND(xtexterior300_telescopeup)
{
  RXGameState* gs = [g_world gameState];

  // play the telescope button movie (code 3)
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 3);
  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 3);

  // if the telescope has no power, we're done
  uint16_t ttelevalve = [gs unsignedShortForKey:@"ttelevalve"];
  if (!ttelevalve)
    return;

  // if the telescope is fully raised, play the "can't move" sound effect
  if ([gs unsignedShortForKey:@"ttelescope"] == 5) {
    uint16_t blocked_sound = [_card dataSoundIDWithName:@"tTelDnMore"];
    DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, blocked_sound, (uint16_t)kRXSoundGainDivisor, 1);
    return;
  }

  // configure telescope raise movie
  [self performSelectorOnMainThread:@selector(_configureTelescopeRaiseMovie) withObject:nil waitUntilDone:YES];

  // play the telescope raise movie (there's 2 of them based on the state of the fissure hatch)
  uint16_t movie_code = ([gs unsignedShortForKey:@"ttelecover"] == 1) ? 4 : 5;
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE, movie_code);

  // play the telescope move sound effect and block on it (it's longer than the movie)
  uint16_t move_sound = [_card dataSoundIDWithName:@"tTeleMove"];
  DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, move_sound, (uint16_t)kRXSoundGainDivisor, 1);

  // refresh the card (which is going to disable the telescope raise movie)
  DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
}

DEFINE_COMMAND(xtexterior300_telescopedown)
{
  RXGameState* gs = [g_world gameState];

  // play the telescope button movie (code 3)
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 3);
  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 3);

  // if the telescope has no power, we're done
  uint16_t ttelevalve = [gs unsignedShortForKey:@"ttelevalve"];
  if (!ttelevalve)
    return;

  uint16_t fissure_hatch = [gs unsignedShortForKey:@"ttelecover"];

  // if the telescope is fully lowered, play the "can't move" sound effect and possibly trigger an ending
  if ([gs unsignedShortForKey:@"ttelescope"] == 1) {
    uint16_t blocked_sound = [_card dataSoundIDWithName:@"tTelDnMore"];

    // if the fissure hatch is open and the telescope pin is disengaged, play the sound effect in the
    // background and trigger the appropriate ending; otherwise, play the sound effect and block on it
    if (fissure_hatch && [gs unsignedShortForKey:@"ttelepin"]) {
      DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, blocked_sound, (uint16_t)kRXSoundGainDivisor, 0);

      // the end!
      [self _playFissureEndgame];
    } else
      DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, blocked_sound, (uint16_t)kRXSoundGainDivisor, 1);

    return;
  }

  // configure telescope lower movie
  [self performSelectorOnMainThread:@selector(_configureTelescopeLowerMovie) withObject:nil waitUntilDone:YES];

  // play the telescope lower movie (there's 2 of them based on the state of the fissure hatch)
  uint16_t movie_code = ([gs unsignedShortForKey:@"ttelecover"] == 1) ? 1 : 2;
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE, movie_code);

  // play the telescope move sound effect and block on it (it's longer than the movie)
  uint16_t move_sound = [_card dataSoundIDWithName:@"tTeleMove"];
  DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, move_sound, (uint16_t)kRXSoundGainDivisor, 1);

  // refresh the card (which is going to disable the telescope lower movie)
  DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
}

DEFINE_COMMAND(xtisland390_covercombo)
{
  uint16_t button = argv[0];
  RXGameState* gs = [g_world gameState];

  // update the current combination with the new button
  uint32_t combo = [gs unsigned32ForKey:@"tcovercombo"];
  uint32_t digits_set = 0;
  for (int i = 0; i < 5; i++) {
    if (!((combo >> (3 * i)) & 0x7))
      break;
    digits_set++;
  }

  // the first digit of the combination is stored in the lsb; we use 3 bits per digit
  combo = combo | ((button & 0x7) << (3 * digits_set));
  [gs setUnsigned32:combo forKey:@"tcovercombo"];

  // if the current combination matches the correct order, enable the opencover hotspot, otherwise disable it
  RXHotspot* cover_hotspot = (RXHotspot*)NSMapGet([_card hotspotsNameMap], @"opencover");
  if (combo == [gs unsigned32ForKey:@"tcorrectorder"])
    DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [cover_hotspot ID]);
  else {
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [cover_hotspot ID]);

    // if 5 digits have been pressed and they did not form the right
    // combination, reset tcovercombo to the button that was just pressed
    if (digits_set == 5)
      [gs setUnsigned32:(button & 0x7)forKey:@"tcovercombo"];
  }
}

#pragma mark -
#pragma mark rebel age

- (void)_playRebelPrisonWindowMovie:(NSTimer*)timer
{
  [event_timer invalidate];
  event_timer = nil;

  // if we're no longer in the rebel prison card, bail out
  if (![[[_card descriptor] simpleDescriptor] isEqual:rebel_prison_window_scdesc])
    return;

  // generate a random MLST index between 2 and 13 and activate it
  uintptr_t mlst_index = rx_rnd_range(2, 13);
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_MLST_AND_START, mlst_index);

  // get the movie's duration (the codes are the same as the MLST in that card)
  // and compute the next movie's delay
  NSTimeInterval delay = 0.0;
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)mlst_index);
  if (movie)
    QTGetTimeInterval([movie duration], &delay);
  delay += 38 + rx_rnd_range(0, 20);

  // store the delay rvillagetime as µseconds
  [[g_world gameState] setUnsigned64:delay * 1E6 forKey:@"rvillagetime"];

  // schedule the event timer
  event_timer = [NSTimer scheduledTimerWithTimeInterval:delay target:self selector:@selector(_playRebelPrisonWindowMovie:) userInfo:nil repeats:NO];
}

DEFINE_COMMAND(xrwindowsetup)
{
  RXGameState* gs = [g_world gameState];

  // remember the card ID, because we need to abort the periodic event if we've switched to a different card
  rebel_prison_window_scdesc = [[[_card descriptor] simpleDescriptor] retain];

  // activate SLST 1 now as a work-around for the late activation by the script
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_SLST, 1);

  // 1/3 times we'll schedule a random prison window movie
  uint32_t initial_guard_roll = rx_rnd_range(0, 2);
  NSTimeInterval next_movie_delay;
  if (initial_guard_roll == 0 && ![gs unsigned32ForKey:@"rrichard"]) {
    // set rrebelview to 0 which will cause the card to paint the guard initially and play MLST 1
    [gs setUnsigned32:0 forKey:@"rrebelview"];

    // schedule the next movie in [0, 20] + 38 seconds
    next_movie_delay = 38 + rx_rnd_range(0, 20);
  } else {
    // normal picture without a guard
    [gs setUnsigned32:1 forKey:@"rrebelview"];

    // schedule the next movie in [0, 20] seconds
    next_movie_delay = rx_rnd_range(0, 20);
  }

  // store the delay rvillagetime as µseconds
  [[g_world gameState] setUnsigned64:next_movie_delay * 1E6 forKey:@"rvillagetime"];

  // schedule the event timer
  [event_timer invalidate];
  event_timer = [NSTimer scheduledTimerWithTimeInterval:next_movie_delay target:self selector:@selector(_playRebelPrisonWindowMovie:) userInfo:nil repeats:NO];
}

DEFINE_COMMAND(xrcredittime)
{
  // there are 2 possible endings when trapping yourself in the Rebel age
  // 1: Gehn free and you get to watch rebels burn you
  // 2: Gehn set loose upon the unsuspecting rebels. pew pew!

  // conveniently, the card activates the proper MLST; both endings use code 1
  [self _endgameWithCode:1 delay:1.5];

  // re-enable the mouse cursor directly, since it was hidden by the trap book handler
  [controller showMouseCursor];
}

DEFINE_COMMAND(xrhideinventory)
{
  // nothing to do here
}

DEFINE_COMMAND(xrshowinventory)
{
  // workaround: set acathbook to 1 if atrapbook is set to 1
  RXGameState* gs = [g_world gameState];
  if ([gs unsigned32ForKey:@"atrapbook"])
    [gs setUnsigned32:1 forKey:@"acathbook"];
}

#pragma mark -
#pragma mark gehn office

DEFINE_COMMAND(xbookclick)
{
  uintptr_t movie_code = argv[0];
  int64_t start_timeval = argv[1];
  int64_t end_timeval = argv[2];
  uint16_t touchbook_index = argv[3];

  RXGameState* gs = [g_world gameState];

  // get the specified touchbook hotspot
  NSString* touchbook_hotspot_name = [NSString stringWithFormat:@"touchbook%hu", touchbook_index];
  RXHotspot* touchbook_hotspot = (RXHotspot*)NSMapGet([_card hotspotsNameMap], touchbook_hotspot_name);
  release_assert(touchbook_hotspot);

  // ogr_b.mov is different from the other trap book movies because it leads
  // to end credits if you don't link; we need to handle it differently
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)movie_code);
  NSString* movie_name = [[[[(RXMovieProxy*)movie archive] valueForKey:@"tMOV"] objectAtIndex:[(RXMovieProxy*)movie ID]] objectForKey:@"Name"];
  release_assert(movie_name);

  BOOL endgame_movie = [movie_name hasSuffix:@"ogr_b.mov"];

  // for the movies where we give the trap book to Gehn, we need to schedule setting atrapbook to 0
  int64_t remove_trap_book_time;
  if ([movie_name hasSuffix:@"ogc_b.mov"])
    remove_trap_book_time = 7200LL;
  else if ([movie_name hasSuffix:@"ogf_b.mov"])
    remove_trap_book_time = 13200LL;
  else
    remove_trap_book_time = 0;

  // we'll need to handle the mouse cursor ourselves since hotspot handling
  // is disabled during script execution

  // busy-wait until we reach the start timestamp
  while (1) {
    // get the current movie time
    QTTime movie_time = [movie _noLockCurrentTime];

    // if we have reached the point where Gehn takes the trap book, set atrapbook to 0
    if (remove_trap_book_time && movie_time.timeValue > remove_trap_book_time) {
      [gs setUnsigned32:0 forKey:@"atrapbook"];
      remove_trap_book_time = 0;
    }

    // if we have gone beyond the link window, exit the mouse tracking loop
    if (movie_time.timeValue > start_timeval)
      break;

    usleep(kRunloopPeriodMicroseconds);
  }

  // get the current mouse vector
  NSRect mouse_vector = [controller mouseVector];

  // set the initial cursor based on the current position of the mouse
  if (NSMouseInRect(mouse_vector.origin, [touchbook_hotspot worldFrame], NO))
    [controller setMouseCursor:RX_CURSOR_OPEN_HAND];
  else
    [controller setMouseCursor:RX_CURSOR_FORWARD];

  // show the mouse cursor; we use the controller directly because although
  // we can assume the cursor is hidden right now, it empirically will not
  // be hidden by the script engine at this point (since the gehn sequence
  // is not a "blocking" movie because of this external
  [controller showMouseCursor];

  // track the mouse until the link window expires, detecting if the player
  // clicks inside the link region and updating the cursor as it enters and
  // exits the link region
  rx_event_t mouse_down_event = [controller lastMouseDownEvent];
  BOOL mouse_was_pressed = NO;
  while (1) {
    // get the current movie time
    QTTime movie_time = [movie _noLockCurrentTime];

    // if we have gone beyond the link window, exit the mouse tracking loop
    if (movie_time.timeValue > end_timeval)
      break;

    // if the mouse has been pressed, update the mouse down event
    rx_event_t event = [controller lastMouseDownEvent];
    if (event.timestamp > mouse_down_event.timestamp) {
      mouse_down_event = event;

      // check where the mouse was pressed, and if it is inside the
      // link region and within the link window, set mouse_was_pressed to
      // YES and exit the loop
      if (NSMouseInRect(mouse_down_event.location, [touchbook_hotspot worldFrame], NO) && movie_time.timeValue > start_timeval) {
        mouse_was_pressed = YES;
        break;
      }
    }

    // update the cursor based on the current position of the mouse
    if (NSMouseInRect(mouse_vector.origin, [touchbook_hotspot worldFrame], NO))
      [controller setMouseCursor:RX_CURSOR_OPEN_HAND];
    else
      [controller setMouseCursor:RX_CURSOR_FORWARD];

    // update the mouse vector
    mouse_vector = [controller mouseVector];

    usleep(kRunloopPeriodMicroseconds);
  }

  // hide the mouse cursor again and reset it to the forward cursor
  [controller hideMouseCursor];
  [controller setMouseCursor:RX_CURSOR_FORWARD];

  // if the mouse was not pressed and this is an endgame movie, start the
  // endgame credits; note that the mouse cursor will be show again
  // automatically when the program execution depth reaches 0
  if (!mouse_was_pressed && endgame_movie) {
    [self _endgameWithCode:movie_code delay:5.0];
    return;
  }
  // otherwise if the mouse was pressed over the link, go into the trap book
  // and execute the trapping Gehn sequence
  else if (mouse_was_pressed) {
    // stop and hide the movie
    DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, movie_code);
    DISPATCH_COMMAND1(RX_COMMAND_STOP_MOVIE, movie_code);

    // start screen update transaction
    DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);

    // schedule a dissolve transition
    RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionDissolve direction:0];
    [controller queueTransition:transition];
    [transition release];

    // enable PLST 3
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 3);

    // end screen update transaction
    DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);

    // play link sound (which is always available as ID 0)
    DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 0, (uint16_t)kRXSoundGainDivisor, 0);

    // hide all movies
    DISPATCH_COMMAND0(RX_COMMAND_DISABLE_ALL_MOVIES);

    // wait 12 seconds
    usleep(12 * 1E6);

    // set ocage to 1
    [gs setUnsigned32:1 forKey:@"ocage"];

    // set agehn to 4 (which indicates that Gehn is trapped)
    [gs setUnsigned32:4 forKey:@"agehn"];

    // set atrapbook to 1 (giving the player the trap book)
    [gs setUnsigned32:1 forKey:@"atrapbook"];

    // play movie with MLST 7 (code 1) and wait until end
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_MLST, 7);
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 1);

    // hide all movies
    DISPATCH_COMMAND0(RX_COMMAND_DISABLE_ALL_MOVIES);

    // schedule a dissolve transition
    transition = [[RXTransition alloc] initWithType:RXTransitionDissolve direction:0];
    [controller queueTransition:transition];
    [transition release];

    // play link sound (which is always available as ID 0)
    DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 0, (uint16_t)kRXSoundGainDivisor, 0);

    // go to card RMAP 10373
    DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, [[_card parent] cardIDFromRMAPCode:10373]);

    // abort the current line of script execution at this point (brings us back to a depth of 0)
    _abortProgramExecution = YES;
  }
  // otherwise just wait for the movie to end
  else
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, movie_code);
}

DEFINE_COMMAND(xorollcredittime)
{
  // there are 3 possible endings when trapping yourself in Riven
  // 1: Gehn is free and you've never met him;
  // 2: Gehn is free and you've talked to him some;
  // 3: Gehn was trapped and is released

  // figure out the proper code based on agehn
  uint32_t gehn_state = [[g_world gameState] unsigned32ForKey:@"agehn"];
  uintptr_t movie_code;
  double delay;
  if (gehn_state == 0) {
    // never spoke to Gehn
    movie_code = 1;
    delay = 9.5;
  } else if (gehn_state == 4) {
    // Gehn was trapped
    movie_code = 2;
    delay = 12.0;
  } else {
    // Spoke with Gehn at least once
    movie_code = 3;
    delay = 8.0;
  }

  // start the endgame credits; the MLST has already been activated
  [self _endgameWithCode:movie_code delay:delay];

  // re-enable the mouse cursor directly, since it was hidden by the trap book handler
  [controller showMouseCursor];
}

DEFINE_COMMAND(xooffice30_closebook)
{
  uint32_t desk_book = [[g_world gameState] unsigned32ForKey:@"odeskbook"];
  if (desk_book != 1)
    return;

  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 1);

  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"closebook") ID]);
  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"null") ID]);
  DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"openbook") ID]);

  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1);
  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 1);

  [[g_world gameState] setUnsigned32:0 forKey:@"odeskbook"];
}

DEFINE_COMMAND(xobedroom5_closedrawer)
{
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE, 2);
  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 1);
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);
  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_MOVIE, 2);

  DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"closedrawer") ID]);
  DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([_card hotspotsNameMap], @"opendrawer") ID]);

  [[g_world gameState] setUnsigned32:0 forKey:@"ostanddrawer"];
}

DEFINE_COMMAND(xgwatch)
{
  uint32_t prison_combo = [[g_world gameState] unsigned32ForKey:@"pcorrectorder"];

  uint16_t combo_sounds[3];
  combo_sounds[0] = [_card dataSoundIDWithName:@"aelev1"];
  combo_sounds[1] = [_card dataSoundIDWithName:@"aelev2"];
  combo_sounds[2] = [_card dataSoundIDWithName:@"aelev3"];

  [self _hideMouseCursor];

  for (uint32_t i = 0; i < 5; i++) {
    DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, combo_sounds[(prison_combo & 0x3) - 1], (uint16_t)kRXSoundGainDivisor, 0);
    prison_combo >>= 2;
    usleep(500 * 1E3);
  }

  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 1);
  DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
}

#pragma mark -
#pragma mark prison

DEFINE_COMMAND(xpisland990_elevcombo)
{
  RXGameState* gs = [g_world gameState];
  uint16_t button = argv[0];

  // play the specified combination sound
  uint16_t combo_sound = [_card dataSoundIDWithName:[NSString stringWithFormat:@"aelev%d", argv[0]]];
  DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, combo_sound, (uint16_t)kRXSoundGainDivisor, 0);

  // if Gehn is not trapped, basically pretend nothing happened
  if ([gs unsigned32ForKey:@"agehn"] != 4)
    return;

  // pelevcombo stores the number of correct digits in the current sequence
  uint32_t correct_digits = [gs unsigned32ForKey:@"pelevcombo"];
  uint32_t prison_combo = [[g_world gameState] unsigned32ForKey:@"pcorrectorder"];
  if (button == ((prison_combo >> (correct_digits << 1)) & 0x3))
    [gs setUnsigned32:correct_digits + 1 forKey:@"pelevcombo"];
  else
    [gs setUnsigned32:0 forKey:@"pelevcombo"];
}

static const uint16_t cath_prison_movie_mlsts0[] = {5, 6, 7, 8};
static const uint16_t cath_prison_movie_mlsts1[] = {11, 14};
static const uint16_t cath_prison_movie_mlsts2[] = {9, 10, 12, 13};

- (void)_playCatherinePrisonMovie:(NSTimer*)timer
{
  [event_timer invalidate];
  event_timer = nil;

  // if we're no longer in the catherine prison card, bail out
  if (![[[_card descriptor] simpleDescriptor] isEqual:cath_prison_scdesc])
    return;

  RXGameState* gs = [g_world gameState];

  // pick a random movie based on catherine's state
  uint16_t movie_mlst;
  if ([gs unsignedShortForKey:@"pcathcheck"] == 0) {
    [gs setUnsigned32:1 forKey:@"pcathcheck"];
    movie_mlst = cath_prison_movie_mlsts0[rx_rnd_range(0, 3)];
  } else if ([gs unsignedShortForKey:@"acathstate"] == 1) {
    movie_mlst = cath_prison_movie_mlsts1[rx_rnd_range(0, 1)];
  } else {
    movie_mlst = cath_prison_movie_mlsts2[rx_rnd_range(0, 3)];
  }

  // update catherine's state based on the selected movie (so that the
  // next selected movie is spacially coherent)
  if (movie_mlst == 5 || movie_mlst == 7 || movie_mlst == 11 || movie_mlst == 14)
    [gs setUnsigned32:2 forKey:@"acathstate"];
  else
    [gs setUnsigned32:1 forKey:@"acathstate"];

  // hide all movies, play the selected movie blocking, then hide all movies again
  DISPATCH_COMMAND0(RX_COMMAND_DISABLE_ALL_MOVIES);
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_MLST_AND_START, movie_mlst);

  // get the movie's duration and compute the next movie's delay
  NSTimeInterval delay = 0.0;
  uintptr_t movie_code = [_card movieCodes][movie_mlst - 1];
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)movie_code);
  if (movie)
    QTGetTimeInterval([movie duration], &delay);
  delay += rx_rnd_range(0, 120); // maybe make this a normal distribution

  // store the delay pcathtime as µseconds
  [[g_world gameState] setUnsigned64:delay * 1E6 forKey:@"pcathtime"];

  // schedule the event timer
  event_timer = [NSTimer scheduledTimerWithTimeInterval:delay target:self selector:@selector(_playCatherinePrisonMovie:) userInfo:nil repeats:NO];
}

#pragma mark -
#pragma mark jungle beetles

- (void)_setPlayBeetleRandomly
{
  // play a beetle movie 1 out of 4 times
  [[g_world gameState] setUnsigned32:(rx_rnd_range(0, 3) == 0) ? 1 : 0 forKey:@"jplaybeetle"];
}

DEFINE_COMMAND(xjplaybeetle_550) { [self _setPlayBeetleRandomly]; }

DEFINE_COMMAND(xjplaybeetle_600) { [self _setPlayBeetleRandomly]; }

DEFINE_COMMAND(xjplaybeetle_950) { [self _setPlayBeetleRandomly]; }

DEFINE_COMMAND(xjplaybeetle_1050) { [self _setPlayBeetleRandomly]; }

DEFINE_COMMAND(xjplaybeetle_1450)
{
  if ([[g_world gameState] unsigned32ForKey:@"jgirl"] != 1)
    [self _setPlayBeetleRandomly];
  else
    [[g_world gameState] setUnsigned32:0 forKey:@"jplaybeetle"];
}

#pragma mark -
#pragma mark jungle lagoon

- (void)_playSunnersMovieWaitingForMouseClick:(RXMovie*)movie setSunnersOnClick:(BOOL)set_sunners
{
  // reset and start the movie if it is not currently playing
  if ([movie rate] == 0.0f) {
    [_movies_to_reset addObject:movie];
    [self performSelectorOnMainThread:@selector(_playMovie:) withObject:movie waitUntilDone:YES];
  }

  // enable the movie
  [controller enableMovie:movie];

  // block until the movie ends or the player presses the mouse button
  rx_event_t mouse_down_event = [controller lastMouseDownEvent];
  BOOL mouse_was_pressed = NO;
  RXHotspot* hotspot = nil;
  NSArray* hotspots = [self activeHotspots];
  while (1) {
    // if the movie is over, bail out of the loop
    if ([movie rate] == 0.0f)
      break;

    // if the mouse has been pressed, bail out of the loop if we hit a hotspot
    rx_event_t event = [controller lastMouseDownEvent];
    if (event.timestamp > mouse_down_event.timestamp) {
      for (hotspot in hotspots) {
        if (NSMouseInRect(event.location, [hotspot worldFrame], NO))
          break;
      }

      if (hotspot) {
        mouse_was_pressed = YES;
        break;
      }
    }

    usleep(kRunloopPeriodMicroseconds);
  }

  // if the mouse was pressed, stop the movie and update jsunners if requested
  if (mouse_was_pressed) {
    [self performSelectorOnMainThread:@selector(_stopMovie:) withObject:movie waitUntilDone:YES];

    if (set_sunners) {
      // only set jsunners if the hotspot was one of the "forward" hotspots
      if (hotspot && [[hotspot name] hasPrefix:@"forward"])
        [[g_world gameState] setUnsigned32:1 forKey:@"jsunners"];
    }
  }
  // otherwise, disable the movie
  else {
    [controller disableMovie:movie];
  }
}

- (void)_handleSunnersUpperStairsEvent
{
  RXGameState* gs = [g_world gameState];
  RXMovie* movie;

  // if the sunners are gone, we're done
  if ([gs unsigned64ForKey:@"jsunners"])
    return;

  // the upper stairs card plays the movie with code 1 in the background, so
  // if that's still playing, we're done
  movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)1);
  if ([(RXMovieProxy*)movie proxiedMovie] && [movie rate] > 0.0f)
    return;

  uint64_t sunners_time = [gs unsigned64ForKey:@"jsunnertime"];

  // if we haven't set a sunner movie delay yet, do so now
  if (sunners_time == 0) {
    sunners_time = RXTimingOffsetTimestamp(RXTimingNow(), rx_rnd_range(2.0, 15.0));
    [gs setUnsigned64:sunners_time forKey:@"jsunnertime"];
  }

  // if the time has not come yet, bail out
  if (sunners_time > RXTimingNow())
    return;

#if defined(DEBUG)
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@playing upper stairs sunners movie {", logPrefix);
  [logPrefix appendString:@"    "];
#endif

  // select a random movie code between 1 and 3 and get the corresponding movie object
  uint16_t movie_code = rx_rnd_range(1, 3);
  movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)(uintptr_t)movie_code);

  // block on the movie or until the mouse is pressed
  [self _playSunnersMovieWaitingForMouseClick:movie setSunnersOnClick:NO];

  // set a new sunner movie time
  [gs setUnsigned64:RXTimingOffsetTimestamp(RXTimingNow(), rx_rnd_range(2.0, 15.0)) forKey:@"jsunnertime"];

#if defined(DEBUG)
  [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
}

- (void)_handleSunnersMidStairsEvent
{
  RXGameState* gs = [g_world gameState];
  RXMovie* movie;

  // xjlagoon700_alert plays the movie with code 1 in the background, so if
  // that's still playing, we're done
  movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)1);
  if ([(RXMovieProxy*)movie proxiedMovie] && [movie rate] > 0.0f)
    return;

  uint64_t sunners_time = [gs unsigned64ForKey:@"jsunnertime"];

  // if we haven't set a sunner movie delay yet, do so now
  if (sunners_time == 0) {
    sunners_time = RXTimingOffsetTimestamp(RXTimingNow(), rx_rnd_range(1.0, 10.0));
    [gs setUnsigned64:sunners_time forKey:@"jsunnertime"];
  }

  // if the time has not come yet, bail out
  if (sunners_time > RXTimingNow())
    return;

#if defined(DEBUG)
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@playing mid stairs sunners movie {", logPrefix);
  [logPrefix appendString:@"    "];
#endif

  // select a random movie code between 2 and 4 (with a bias toward 4) and get the corresponding movie object
  long r = rx_rnd_range(0, 5);
  uint16_t movie_code;
  if (r == 4)
    movie_code = 2;
  else if (r == 5)
    movie_code = 3;
  else
    movie_code = 4;
  movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)(uintptr_t)movie_code);

  // block on the movie or until the mouse is pressed
  [self _playSunnersMovieWaitingForMouseClick:movie setSunnersOnClick:NO];

  // set a new sunner movie time
  [gs setUnsigned64:RXTimingOffsetTimestamp(RXTimingNow(), rx_rnd_range(1.0, 10.0)) forKey:@"jsunnertime"];

#if defined(DEBUG)
  [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
}

- (void)_handleSunnersLowerStairsEvent
{
  RXGameState* gs = [g_world gameState];
  RXMovie* movie;

  // xjlagoon800_alert plays the movie with code 1 in the background, so if
  // that's still playing, we're done
  movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)1);
  if ([(RXMovieProxy*)movie proxiedMovie] && [movie rate] > 0.0f)
    return;

  uint64_t sunners_time = [gs unsigned64ForKey:@"jsunnertime"];

  // if we haven't set a sunner movie delay yet, do so now
  if (sunners_time == 0) {
    sunners_time = RXTimingOffsetTimestamp(RXTimingNow(), rx_rnd_range(1.0, 30.0));
    [gs setUnsigned64:sunners_time forKey:@"jsunnertime"];
  }

  // if the time has not come yet, bail out
  if (sunners_time > RXTimingNow())
    return;

#if defined(DEBUG)
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@playing lower stairs sunners movie {", logPrefix);
  [logPrefix appendString:@"    "];
#endif

  // select a random movie code between 3 and 5 and get the corresponding movie object
  uint16_t movie_code = rx_rnd_range(3, 5);
  movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)(uintptr_t)movie_code);

  // block on the movie or until the mouse is pressed
  [self _playSunnersMovieWaitingForMouseClick:movie setSunnersOnClick:NO];

  // set a new sunner movie time
  [gs setUnsigned64:RXTimingOffsetTimestamp(RXTimingNow(), rx_rnd_range(1.0, 30.0)) forKey:@"jsunnertime"];

#if defined(DEBUG)
  [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
}

- (void)_handleSunnersBeachEvent
{
  RXGameState* gs = [g_world gameState];
  RXMovie* movie;

  // xjlagoon1500_alert plays the movie with code 3 in the background, so if
  // that's still playing, we're done
  movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)3);
  if ([(RXMovieProxy*)movie proxiedMovie] && [movie rate] > 0.0f)
    return;

  uint64_t sunners_time = [gs unsigned64ForKey:@"jsunnertime"];

  // if we haven't set a sunner movie delay yet, do so now
  if (sunners_time == 0) {
    sunners_time = RXTimingOffsetTimestamp(RXTimingNow(), rx_rnd_range(1.0, 30.0));
    [gs setUnsigned64:sunners_time forKey:@"jsunnertime"];
  }

  // if the time has not come yet, bail out
  if (sunners_time > RXTimingNow())
    return;

#if defined(DEBUG)
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@playing beach sunners movie {", logPrefix);
  [logPrefix appendString:@"    "];
#endif

  // select a random MLST between 3 and 8 and play the movie blocking (the movie codes match the MLST index)
  uint16_t movie_mlst = rx_rnd_range(3, 8);
  DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_MLST, movie_mlst);
  DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, movie_mlst);

  // show the mouse cursor again (since the movie blocking command will have hidden it)
  [self _showMouseCursor];

  // set a new sunner movie time
  [gs setUnsigned64:RXTimingOffsetTimestamp(RXTimingNow(), rx_rnd_range(1.0, 30.0)) forKey:@"jsunnertime"];

#if defined(DEBUG)
  [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
  RXLog(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
}

- (void)_handleSunnersIdleEvent:(NSTimer*)timer
{
  // if the sunners are gone, we're done
  if ([[g_world gameState] unsigned64ForKey:@"jsunners"]) {
    [event_timer invalidate];
    event_timer = nil;
    return;
  }

  RXCardDescriptor* cdesc = [_card descriptor];
  if ([cdesc isCardWithRMAP:sunners_upper_stairs_rmap stackName:@"jspit"])
    [self _handleSunnersUpperStairsEvent];
  else if ([cdesc isCardWithRMAP:sunners_mid_stairs_rmap stackName:@"jspit"])
    [self _handleSunnersMidStairsEvent];
  else if ([cdesc isCardWithRMAP:sunners_lower_stairs_rmap stackName:@"jspit"])
    [self _handleSunnersLowerStairsEvent];
  else if ([cdesc isCardWithRMAP:sunners_beach_rmap stackName:@"jspit"])
    [self _handleSunnersBeachEvent];
  else {
    [event_timer invalidate];
    event_timer = nil;
  }
}

DEFINE_COMMAND(xjlagoon700_alert)
{
  if ([[g_world gameState] unsigned32ForKey:@"jsunners"])
    return;

  // re-enable hotspot processing in the controller at this time
  [controller enableHotspotHandling];

  // play movie with code 1 and block until the end of the movie or the player
  // moves; if the player moves, we'll update jsunners
  RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)1);
  [self _playSunnersMovieWaitingForMouseClick:movie setSunnersOnClick:YES];

  // disable hotspot processing to balance the counter
  [controller disableHotspotHandling];
}

DEFINE_COMMAND(xjlagoon800_alert)
{
  uint32_t sunners = [[g_world gameState] unsigned32ForKey:@"jsunners"];
  if (!sunners) {
    // re-enable hotspot processing in the controller at this time
    [controller enableHotspotHandling];

    // play movie with code 1 and block until the end of the movie or the player
    // moves; if the player moves, we'll update jsunners
    RXMovie* movie = (RXMovie*)NSMapGet(code_movie_map, (const void*)1);
    [self _playSunnersMovieWaitingForMouseClick:movie setSunnersOnClick:YES];

    // disable hotspot processing to balance the counter
    [controller disableHotspotHandling];
  } else if (sunners == 1) {
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 6);

    [[g_world gameState] setUnsigned32:2 forKey:@"jsunners"];
  }
}

DEFINE_COMMAND(xjlagoon1500_alert)
{
  uint32_t sunners = [[g_world gameState] unsigned32ForKey:@"jsunners"];
  if (!sunners) {
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 3);
  } else if (sunners == 1) {
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);
    [[g_world gameState] setUnsigned32:2 forKey:@"jsunners"];
  }
}

DEFINE_COMMAND(xflies) {}

@end
