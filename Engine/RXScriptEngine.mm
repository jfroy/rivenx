//
//  RXScriptEngine.m
//  rivenx
//
//  Created by Jean-Francois Roy on 31/01/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <assert.h>
#import <limits.h>
#import <stdbool.h>
#import <unistd.h>

#import <mach/task.h>
#import <mach/thread_act.h>
#import <mach/thread_policy.h>

#import <OpenGL/CGLMacro.h>

#import <objc/runtime.h>

#import "Engine/RXScriptDecoding.h"
#import "Engine/RXScriptEngine.h"
#import "Engine/RXScriptCommandAliases.h"
#import "Engine/RXWorldProtocol.h"
#import "Engine/RXEditionManager.h"
#import "Engine/RXCursors.h"

#import "Rendering/Graphics/RXTransition.h"
#import "Rendering/Graphics/RXPicture.h"
#import "Rendering/Graphics/RXDynamicPicture.h"
#import "Rendering/Graphics/RXMovieProxy.h"


static const NSTimeInterval k_mouse_tracking_loop_period = 0.001;

struct rx_card_dynamic_picture {
    GLuint texture;
};

typedef void (*rx_command_imp_t)(id, SEL, const uint16_t, const uint16_t*);
struct _rx_command_dispatch_entry {
    rx_command_imp_t imp;
    SEL sel;
};
typedef struct _rx_command_dispatch_entry rx_command_dispatch_entry_t;

static const uint32_t rx_command_count = 48;
static rx_command_dispatch_entry_t _riven_command_dispatch_table[rx_command_count];
static NSMapTable* _riven_external_command_dispatch_map;

#define DEFINE_COMMAND(NAME) - (void)_external_ ## NAME:(const uint16_t)argc arguments:(const uint16_t*)argv
#define COMMAND_SELECTOR(NAME) @selector(_external_ ## NAME:arguments:)

CF_INLINE void rx_dispatch_commandv(id target, rx_command_dispatch_entry_t* command, uint16_t argc, uint16_t* argv) {
    command->imp(target, command->sel, argc, argv);
}

CF_INLINE void rx_dispatch_command0(id target, rx_command_dispatch_entry_t* command) {
    uint16_t args;
    rx_dispatch_commandv(target, command, 0, &args);
}

CF_INLINE void rx_dispatch_command1(id target, rx_command_dispatch_entry_t* command, uint16_t a1) {
    uint16_t args[] = {a1};
    rx_dispatch_commandv(target, command, 1, args);
}

CF_INLINE void rx_dispatch_command2(id target, rx_command_dispatch_entry_t* command, uint16_t a1, uint16_t a2) {
    uint16_t args[] = {a1, a2};
    rx_dispatch_commandv(target, command, 2, args);
}

CF_INLINE void rx_dispatch_command3(id target, rx_command_dispatch_entry_t* command, uint16_t a1, uint16_t a2, uint16_t a3) {
    uint16_t args[] = {a1, a2, a3};
    rx_dispatch_commandv(target, command, 3, args);
}

CF_INLINE void rx_dispatch_command4(id target, rx_command_dispatch_entry_t* command, uint16_t a1, uint16_t a2, uint16_t a3, uint16_t a4) {
    uint16_t args[] = {a1, a2, a3, a4};
    rx_dispatch_commandv(target, command, 4, args);
}

CF_INLINE void rx_dispatch_command5(id target, rx_command_dispatch_entry_t* command, uint16_t a1, uint16_t a2, uint16_t a3, uint16_t a4, uint16_t a5) {
    uint16_t args[] = {a1, a2, a3, a4, a5};
    rx_dispatch_commandv(target, command, 5, args);
}

#define DISPATCH_COMMANDV(COMMAND_INDEX, ARGC, ARGV) rx_dispatch_commandv(self, _riven_command_dispatch_table + COMMAND_INDEX, ARGC, ARGV)
#define DISPATCH_COMMAND0(COMMAND_INDEX) rx_dispatch_command0(self, _riven_command_dispatch_table + COMMAND_INDEX)
#define DISPATCH_COMMAND1(COMMAND_INDEX, ARG1) rx_dispatch_command1(self, _riven_command_dispatch_table + COMMAND_INDEX, ARG1)
#define DISPATCH_COMMAND2(COMMAND_INDEX, ARG1, ARG2) rx_dispatch_command2(self, _riven_command_dispatch_table + COMMAND_INDEX, ARG1, ARG2)
#define DISPATCH_COMMAND3(COMMAND_INDEX, ARG1, ARG2, ARG3) rx_dispatch_command3(self, _riven_command_dispatch_table + COMMAND_INDEX, ARG1, ARG2, ARG3)
#define DISPATCH_COMMAND4(COMMAND_INDEX, ARG1, ARG2, ARG3, ARG4) rx_dispatch_command4(self, _riven_command_dispatch_table + COMMAND_INDEX, ARG1, ARG2, ARG3, ARG4)
#define DISPATCH_COMMAND5(COMMAND_INDEX, ARG1, ARG2, ARG3, ARG4, ARG5) rx_dispatch_command5(self, _riven_command_dispatch_table + COMMAND_INDEX, ARG1, ARG2, ARG3, ARG4, ARG5)

CF_INLINE void rx_dispatch_externalv(id target, NSString* external_name, uint16_t argc, uint16_t* argv) {
    rx_command_dispatch_entry_t* command = (rx_command_dispatch_entry_t*)NSMapGet(_riven_external_command_dispatch_map,
                                                                                  [external_name lowercaseString]);
    command->imp(target, command->sel, argc, argv);
}

CF_INLINE void rx_dispatch_external0(id target, NSString* external_name) {
    uint16_t args;
    rx_dispatch_externalv(target, external_name, 0, &args);
}

CF_INLINE void rx_dispatch_external1(id target, NSString* external_name, uint16_t a1) {
    uint16_t args[] = {a1};
    rx_dispatch_externalv(target, external_name, 1, args);
}


@interface RXScriptEngine (RXScriptOpcodes)
- (void)_opcode_activateSLST:(const uint16_t)argc arguments:(const uint16_t*)argv;
@end

@implementation RXScriptEngine

+ (void)initialize {
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
    _riven_command_dispatch_table[38].sel = @selector(_opcode_complexStartMovie:arguments:);
    _riven_command_dispatch_table[39].sel = @selector(_opcode_activatePLST:arguments:);
    _riven_command_dispatch_table[40].sel = @selector(_opcode_activateSLST:arguments:);
    _riven_command_dispatch_table[41].sel = @selector(_opcode_activateMLSTAndStartMovie:arguments:);
    _riven_command_dispatch_table[42].sel = @selector(_opcode_noop:arguments:);
    _riven_command_dispatch_table[43].sel = @selector(_opcode_activateBLST:arguments:);
    _riven_command_dispatch_table[44].sel = @selector(_opcode_activateFLST:arguments:);
    _riven_command_dispatch_table[45].sel = @selector(_opcode_unimplemented:arguments:); // is "do zip"
    _riven_command_dispatch_table[46].sel = @selector(_opcode_activateMLST:arguments:);
    _riven_command_dispatch_table[47].sel = @selector(_opcode_activateSLSTWithVolume:arguments:);
    
    for (unsigned char selectorIndex = 0; selectorIndex < rx_command_count; selectorIndex++)
        _riven_command_dispatch_table[selectorIndex].imp =
            (rx_command_imp_t)[self instanceMethodForSelector:_riven_command_dispatch_table[selectorIndex].sel];
    
    // search for external command implementation methods and register them
    _riven_external_command_dispatch_map = NSCreateMapTable(NSObjectMapKeyCallBacks, NSNonRetainedObjectMapValueCallBacks, 0);
    
    NSCharacterSet* colon_character_set = [NSCharacterSet characterSetWithCharactersInString:@":"];
    
    void* iterator = 0;
    struct objc_method_list* mlist;
    while ((mlist = class_nextMethodList(self, &iterator))) {
        for (int method_index = 0; method_index < mlist->method_count; method_index++) {
            Method m = mlist->method_list + method_index;
            NSString* method_selector_string = NSStringFromSelector(m->method_name);
            if ([method_selector_string hasPrefix:@"_external_"]) {
                NSRange first_colon_range = [method_selector_string rangeOfCharacterFromSet:colon_character_set options:NSLiteralSearch];
                NSString* external_name = [[method_selector_string substringWithRange:NSMakeRange([(NSString*)@"_external_" length],
                                                                                                  first_colon_range.location - [(NSString*)@"_external_" length])]
                                           lowercaseString];
#if defined(DEBUG) && DEBUG > 1
                RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"registering external command: %@", external_name);
#endif
                rx_command_dispatch_entry_t* command_dispatch = (rx_command_dispatch_entry_t*)malloc(sizeof(rx_command_dispatch_entry_t));
                command_dispatch->sel = m->method_name;
                command_dispatch->imp = (rx_command_imp_t)m->method_imp;
                NSMapInsertKnownAbsent(_riven_external_command_dispatch_map, external_name, command_dispatch);
            }
        }
    }
}

+ (BOOL)accessInstanceVariablesDirectly {
    return NO;
}

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithController:(id<RXScriptEngineControllerProtocol>)ctlr {
    NSError* error;
    kern_return_t kerr;
    
    self = [super init];
    if (!self)
        return nil;
    
    controller = ctlr;
    
    logPrefix = [NSMutableString new];
    
    _activeHotspotsLock = OS_SPINLOCK_INIT;
    _activeHotspots = [NSMutableArray new];
    
    code2movieMap = NSCreateMapTable(NSIntMapKeyCallBacks, NSObjectMapValueCallBacks, 0);
    _dynamicPictureMap = NSCreateMapTable(NSIntMapKeyCallBacks, NSOwnedPointerMapValueCallBacks, 0);
    
    _movies_to_reset = [NSMutableSet new];
    
    kerr = semaphore_create(mach_task_self(), &_moviePlaybackSemaphore, SYNC_POLICY_FIFO, 0);
    if (kerr != 0) {
        [self release];
        error = [NSError errorWithDomain:NSMachErrorDomain code:kerr userInfo:nil];
        @throw [NSException exceptionWithName:@"RXSystemResourceException"
                                       reason:@"Could not create the movie playback semaphore."
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    }
    
    _screen_update_disable_counter = 0;
    
    _movie_collection_timer = [NSTimer scheduledTimerWithTimeInterval:10*60.0 target:self selector:@selector(_collectMovies:) userInfo:nil repeats:YES];
    
    // initialize gameplay support variables
    
    // sliders are packed to the left
    sliders_state = 0x1F00000;
    
    // default dome slider background display origin
    dome_slider_background_position.x = 200;
    dome_slider_background_position.y = 250;
    
    // the trapeze rect is emcompasses the bottom part of the trapeze on jspit 276
    trapeze_rect = NSMakeRect(310, 172, 16, 36);
    
    return self;
}

- (void)dealloc {
    // lock the GL context and clean up textures and GL buffers
    CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
    CGLLockContext(cgl_ctx);
    
    if (_dynamicPictureMap) {
        NSMapEnumerator dynamicPictureEnum = NSEnumerateMapTable(_dynamicPictureMap);
        uintptr_t key;
        struct rx_card_dynamic_picture* value;
        while (NSNextMapEnumeratorPair(&dynamicPictureEnum, (void**)&key, (void**)&value))
            glDeleteTextures(1, &value->texture);
        
        NSFreeMapTable(_dynamicPictureMap);
    }
    
    glFlush();
    CGLUnlockContext(cgl_ctx);
    
    [_movie_collection_timer invalidate];
    if (_moviePlaybackSemaphore)
        semaphore_destroy(mach_task_self(), _moviePlaybackSemaphore);
    if (code2movieMap)
        NSFreeMapTable(code2movieMap);
    [_movies_to_reset release];
    
    [_synthesizedSoundGroup release];
    
    [logPrefix release];
    [_activeHotspots release];
    
    [card release];
    
    [super dealloc];
}

- (NSString*)description {
    // this is mostly a hack to avoid printing anything in the script log
    return @"";
}

- (void)setCard:(RXCard*)c {
    if (c == card)
        return;
    
#if defined(DEBUG)
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"setting card to %@", c);
#endif
    
    id old = card;
    card = [c retain];
    [old release];
}

#pragma mark -
#pragma mark script execution

- (size_t)_executeRivenProgram:(const void*)program count:(uint16_t)opcodeCount {
    if (!controller)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"NO RIVEN SCRIPT HANDLER" userInfo:nil];
    
    RXStack* parent = [[card descriptor] parent];
    
    // if this is a top-level execution, reset the previous opcodes array
    if (_programExecutionDepth == 0) {
        _previous_opcodes[0] = UINT16_MAX;
        _previous_opcodes[1] = UINT16_MAX;
    }
    
    // bump the execution depth
    _programExecutionDepth++;
    
    size_t programOffset = 0;
    const uint16_t* shortedProgram = (uint16_t *)program;
    
    uint16_t pc = 0;
    for (; pc < opcodeCount; pc++) {
        if (_abortProgramExecution)
            break;
        
        if (*shortedProgram == 8) {
            // parameters for the conditional branch opcode
            uint16_t argc = *(shortedProgram + 1);
            uint16_t varID = *(shortedProgram + 2);
            uint16_t caseCount = *(shortedProgram + 3);
            
            // adjust the shorted program
            programOffset += 8;
            shortedProgram = (uint16_t*)BUFFER_OFFSET(program, programOffset);
            
            // argc should always be 2 for a conditional branch
            if (argc != 2)
                @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
            
            // get the variable from the game state
            NSString* name = [parent varNameAtIndex:varID];
            if (!name)
                name = [NSString stringWithFormat:@"%@%hu", [parent key], varID];
            uint16_t varValue = [[g_world gameState] unsignedShortForKey:name];
            
#if defined(DEBUG)
            RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@switch statement on variable %@=%hu", logPrefix, name, varValue);
#endif
            
            // evaluate each branch
            uint16_t caseIndex = 0;
            uint16_t caseValue;
            size_t defaultCaseOffset = 0;
            for (; caseIndex < caseCount; caseIndex++) {
                caseValue = *shortedProgram;
                
                // record the address of the default case in case we need to execute it if we don't find a matching case
                if (caseValue == 0xffff)
                    defaultCaseOffset = programOffset;
                
                // matching case
                if (caseValue == varValue) {
#if defined(DEBUG)
                    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@executing matching case {", logPrefix);
                    [logPrefix appendString:@"    "];
#endif
                    
                    // execute the switch statement program
                    programOffset += [self _executeRivenProgram:(shortedProgram + 2) count:*(shortedProgram + 1)];
                    
#if defined(DEBUG)
                    [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
                    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
                } else {
                    programOffset += rx_compute_riven_script_length((shortedProgram + 2), *(shortedProgram + 1), false); // skip over the case
                }
                
                // adjust the shorted program
                programOffset += 4; // account for the case value and case instruction count
                shortedProgram = (uint16_t*)BUFFER_OFFSET(program, programOffset);
                
                // bail out if we executed a matching case
                if (caseValue == varValue)
                    break;
            }
            
            // if we didn't match any case, execute the default case
            if (caseIndex == caseCount && defaultCaseOffset != 0) {
#if defined(DEBUG)
                RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@no case matched variable value, executing default case {", logPrefix);
                [logPrefix appendString:@"    "];
#endif
                
                // execute the switch statement program
                [self _executeRivenProgram:((uint16_t*)BUFFER_OFFSET(program, defaultCaseOffset)) + 2
                                     count:*(((uint16_t*)BUFFER_OFFSET(program, defaultCaseOffset)) + 1)];
                
#if defined(DEBUG)
                [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
                RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
            } else {
                // skip over the instructions of the remaining cases
                caseIndex++;
                for (; caseIndex < caseCount; caseIndex++) {
                    programOffset += rx_compute_riven_script_length((shortedProgram + 2), *(shortedProgram + 1), false) + 4;
                    shortedProgram = (uint16_t*)BUFFER_OFFSET(program, programOffset);
                }
            }
        } else {
            // execute the command
            _riven_command_dispatch_table[*shortedProgram].imp(self, _riven_command_dispatch_table[*shortedProgram].sel,
                                                               *(shortedProgram + 1), shortedProgram + 2);
            _previous_opcodes[1] = _previous_opcodes[0];
            _previous_opcodes[0] = *shortedProgram;
            
            // adjust the shorted program
            programOffset += 4 + (*(shortedProgram + 1) * sizeof(uint16_t));
            shortedProgram = (uint16_t*)BUFFER_OFFSET(program, programOffset);          
        }
    }
    
    // bump down the execution depth
#if defined(DEBUG)
    assert(_programExecutionDepth > 0);
#endif
    _programExecutionDepth--;
    if (_programExecutionDepth == 0)
        _abortProgramExecution = NO;
    
    return programOffset;
}

- (void)_runScreenUpdatePrograms {
#if defined(DEBUG)
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@screen update {", logPrefix);
    [logPrefix appendString:@"    "];
#endif
    
    // this is a bit of a hack, but disable screen updates while running screen update programs
    _screen_update_disable_counter++;
    
    NSArray* programs = [[card events] objectForKey:RXScreenUpdateScriptKey];
    uint32_t programCount = [programs count];
    uint32_t programIndex = 0;
    for (; programIndex < programCount; programIndex++) {
        NSDictionary* program = [programs objectAtIndex:programIndex];
        [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes]
                             count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
    }
    
    // re-enable screen updates to match the disable we did above
    if (_screen_update_disable_counter > 0)
        _screen_update_disable_counter--;
    
#if defined(DEBUG)
    [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
}

- (void)_updateScreen {
    // WARNING: THIS IS NOT THREAD SAFE, BUT DOES NOT INTERFERE WITH THE RENDER THREAD
    
    // if screen updates are disabled, return immediatly
    if (_screen_update_disable_counter > 0) {
#if defined(DEBUG)
        if (!_doing_screen_update)
            RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@    screen update command dropped because updates are disabled", logPrefix);
#endif
        return;
    }

    // run screen update programs
    if (!_disable_screen_update_programs) {
        _doing_screen_update = YES;
        [self _runScreenUpdatePrograms];
        _doing_screen_update = NO;
    } else
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@screen update (programs disabled)", logPrefix);
    
    // some cards disable screen updates during screen update programs, so we
    // need to decrement the counter here to function properly; see tspit 229
    // open card
    if (_screen_update_disable_counter > 0)
        _screen_update_disable_counter--;
    
    // the script handler will set our front render state to our back render
    // state at the appropriate moment; when this returns, the swap has occured
    // (front == back)
    [controller update];
}

#pragma mark -

- (void)openCard {
#if defined(DEBUG)
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@opening card {", logPrefix);
    [logPrefix appendString:@"    "];
#endif

    // retain the card while it executes programs
    RXCard* executing_card = card;
    if (_programExecutionDepth == 0) {
        [executing_card retain];
    }

    // disable screen updates
    DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);
    
    // clear all active hotspots and replace them with the new card's hotspots
    OSSpinLockLock(&_activeHotspotsLock);
    [_activeHotspots removeAllObjects];
    [_activeHotspots addObjectsFromArray:[card hotspots]];
    [_activeHotspots makeObjectsPerformSelector:@selector(enable)];
    [_activeHotspots sortUsingSelector:@selector(compareByIndex:)];
    OSSpinLockUnlock(&_activeHotspotsLock);
    
    // reset auto-activation states
    _did_activate_plst = NO;
    _did_activate_slst = NO;
    
    // reset the transition queue flag
    _queuedAPushTransition = NO;
    
    // reset water animation
    [controller queueSpecialEffect:NULL owner:card];
    
    // disable all movies on the next screen refresh (bad drawing glitches occur if this is not done, see bspit 163)
    [controller disableAllMoviesOnNextScreenUpdate];
    
    // execute card open programs
    NSArray* programs = [[card events] objectForKey:RXCardOpenScriptKey];
    assert(programs);
    
    uint32_t programCount = [programs count];
    uint32_t programIndex = 0;
    for(; programIndex < programCount; programIndex++) {
        NSDictionary* program = [programs objectAtIndex:programIndex];
        [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes]
                             count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
    }
    
    // activate the first picture if none has been enabled already
    if ([card pictureCount] > 0 && !_did_activate_plst) {
#if defined(DEBUG)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@automatically activating first plst record", logPrefix);
#endif
        DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1);
    }
    
    // workarounds
    RXSimpleCardDescriptor* ecsd = [[executing_card descriptor] simpleDescriptor];
    
    // dome combination card - if the dome combination is 1-2-3-4-5, the opendome hotspot won't get enabled, so do it here
    if ([ecsd isEqual:[[RXEditionManager sharedEditionManager] lookupCardWithKey:@"jdome combo"]]) {
        // check if the sliders match the dome configuration
        uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
        if (sliders_state == domecombo) {
            DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"resetsliders") ID]);
            DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"opendome") ID]);
        }
    }
    
    // force a screen update
    _screen_update_disable_counter = 1;
     DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
     
     // now run the start rendering programs
     [self startRendering];
     
#if defined(DEBUG)
    [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
    
    // release the card if it no longer is executing programs
    if (_programExecutionDepth == 0) {
        [executing_card release];
        
        // if the card hid the mouse cursor while executing programs, we can now show it again
        if (_did_hide_mouse) {
            [controller showMouseCursor];
            _did_hide_mouse = NO;
        }
    }
}

- (void)startRendering {
#if defined(DEBUG)
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@starting rendering {", logPrefix);
    [logPrefix appendString:@"    "];
#endif

    // retain the card while it executes programs
    RXCard* executing_card = card;
    if (_programExecutionDepth == 0) {
        [executing_card retain];
    }
    
    // execute rendering programs (index 9)
    NSArray* programs = [[card events] objectForKey:RXStartRenderingScriptKey];
    assert(programs);
    
    uint32_t programCount = [programs count];
    uint32_t programIndex = 0;
    for (; programIndex < programCount; programIndex++) {
        NSDictionary* program = [programs objectAtIndex:programIndex];
        [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes]
                             count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
    }
    
    // activate the first sound group if none has been enabled already
    if ([[card soundGroups] count] > 0 && !_did_activate_slst) {
#if defined(DEBUG)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@automatically activating first slst record", logPrefix);
#endif
        [controller activateSoundGroup:[[card soundGroups] objectAtIndex:0]];
        _did_activate_slst = YES;
    }
    
#if defined(DEBUG)
    [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

    // release the card if it no longer is executing programs
    if (_programExecutionDepth == 0) {
        [executing_card release];
        
        // if the card hid the mouse cursor while executing programs, we can now show it again
        if (_did_hide_mouse) {
            [controller showMouseCursor];
            _did_hide_mouse = NO;
        }
    }
}

- (void)closeCard {
    // we may be switching from the NULL card, so check for that and return immediately if that's the case
    if (!card)
        return;

#if defined(DEBUG)
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@closing card {", logPrefix);
    [logPrefix appendString:@"    "];
#endif
    
    // retain the card while it executes programs
    RXCard* executing_card = card;
    if (_programExecutionDepth == 0) {
        [executing_card retain];
    }
    
    // execute leaving programs (index 7)
    NSArray* programs = [[card events] objectForKey:RXCardCloseScriptKey];
    assert(programs);
    
    uint32_t programCount = [programs count];
    uint32_t programIndex = 0;
    for (; programIndex < programCount; programIndex++) {
        NSDictionary* program = [programs objectAtIndex:programIndex];
        [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes]
                             count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
    }
    
#if defined(DEBUG)
    [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

    // release the card if it no longer is executing programs
    if (_programExecutionDepth == 0) {
        [executing_card release];
        
        // if the card hid the mouse cursor while executing programs, we can now show it again
        if (_did_hide_mouse) {
            [controller showMouseCursor];
            _did_hide_mouse = NO;
        }
    }
}

#pragma mark -
#pragma mark hotspots

- (NSArray*)activeHotspots {
    // WARNING: WILL BE CALLED BY THE MAIN THREAD
    
    OSSpinLockLock(&_activeHotspotsLock);
    NSArray* hotspots = [[_activeHotspots copy] autorelease];
    OSSpinLockUnlock(&_activeHotspotsLock);
    
    return hotspots;
}

- (void)mouseInsideHotspot:(RXHotspot*)hotspot {
    if (!hotspot)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"hotspot CANNOT BE NIL" userInfo:nil];

#if defined(DEBUG)
#if DEBUG > 2
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouse inside %@ {", logPrefix, hotspot);
    [logPrefix appendString:@"    "];
#endif
    _disableScriptLogging = YES;
#endif
    
    // retain the card while it executes programs
    RXCard* executing_card = card;
    if (_programExecutionDepth == 0) {
        [executing_card retain];
    }
    
    // keep a weak reference to the hotspot while executing within the context of this hotspot handler
    _current_hotspot = hotspot;
    
    // execute mouse moved programs (index 4)
    NSArray* programs = [[hotspot script] objectForKey:RXMouseInsideScriptKey];
    assert(programs);
    
    uint32_t programCount = [programs count];
    uint32_t programIndex = 0;
    for (; programIndex < programCount; programIndex++) {
        NSDictionary* program = [programs objectAtIndex:programIndex];
        [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes]
                             count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
    }
    
#if defined(DEBUG)
    _disableScriptLogging = NO;
#if DEBUG > 2
    [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
#endif

    // release the card if it no longer is executing programs
    if (_programExecutionDepth == 0) {
        [executing_card release];
        _current_hotspot = nil;
        
        // if the card hid the mouse cursor while executing programs, we can now show it again
        if (_did_hide_mouse) {
            [controller showMouseCursor];
            _did_hide_mouse = NO;
        }
    }
}

- (void)mouseExitedHotspot:(RXHotspot*)hotspot {
    if (!hotspot)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"hotspot CANNOT BE NIL" userInfo:nil];

#if defined(DEBUG)
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouse exited %@ {", logPrefix, hotspot);
    [logPrefix appendString:@"    "];
#endif
    
    // retain the card while it executes programs
    RXCard* executing_card = card;
    if (_programExecutionDepth == 0) {
        [executing_card retain];
    }
    
    // keep a weak reference to the hotspot while executing within the context of this hotspot handler
    _current_hotspot = hotspot;
    
    // execute mouse leave programs (index 5)
    NSArray* programs = [[hotspot script] objectForKey:RXMouseExitedScriptKey];
    assert(programs);
    
    uint32_t programCount = [programs count];
    uint32_t programIndex = 0;
    for (; programIndex < programCount; programIndex++) {
        NSDictionary* program = [programs objectAtIndex:programIndex];
        [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes]
                             count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
    }
    
#if defined(DEBUG)
    [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

    // release the card if it no longer is executing programs
    if (_programExecutionDepth == 0) {
        [executing_card release];
        _current_hotspot = nil;
        
        // if the card hid the mouse cursor while executing programs, we can now show it again
        if (_did_hide_mouse) {
            [controller showMouseCursor];
            _did_hide_mouse = NO;
        }
    }
}

- (void)mouseDownInHotspot:(RXHotspot*)hotspot {
    if (!hotspot)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"hotspot CANNOT BE NIL" userInfo:nil];

#if defined(DEBUG)
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouse down in %@ {", logPrefix, hotspot);
    [logPrefix appendString:@"    "];
#endif
    
    // retain the card while it executes programs
    RXCard* executing_card = card;
    if (_programExecutionDepth == 0) {
        [executing_card retain];
    }
    
    // keep a weak reference to the hotspot while executing within the context of this hotspot handler
    _current_hotspot = hotspot;
    
    // execute mouse down programs (index 0)
    NSArray* programs = [[hotspot script] objectForKey:RXMouseDownScriptKey];
    assert(programs);
    
    uint32_t programCount = [programs count];
    uint32_t programIndex = 0;
    for (; programIndex < programCount; programIndex++) {
        NSDictionary* program = [programs objectAtIndex:programIndex];
        [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes]
                             count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
    }
    
#if defined(DEBUG)
    [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

    // release the card if it no longer is executing programs
    if (_programExecutionDepth == 0) {
        [executing_card release];
        _current_hotspot = nil;
        
        // if the card hid the mouse cursor while executing programs, we can now show it again
        if (_did_hide_mouse) {
            [controller showMouseCursor];
            _did_hide_mouse = NO;
        }
    }
    
    // we need to enable hotspot handling at the end of mouse down messages
    [controller enableHotspotHandling];
}

- (void)mouseUpInHotspot:(RXHotspot*)hotspot {
    if (!hotspot)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"hotspot CANNOT BE NIL" userInfo:nil];

#if defined(DEBUG)
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouse up in %@ {", logPrefix, hotspot);
    [logPrefix appendString:@"    "];
#endif

    // retain the card while it executes programs
    RXCard* executing_card = card;
    if (_programExecutionDepth == 0) {
        [executing_card retain];
    }
    
    // keep a weak reference to the hotspot while executing within the context of this hotspot handler
    _current_hotspot = hotspot;
    
    // execute mouse up programs (index 2)
    NSArray* programs = [[hotspot script] objectForKey:RXMouseUpScriptKey];
    assert(programs);
    
    uint32_t programCount = [programs count];
    uint32_t programIndex = 0;
    for (; programIndex < programCount; programIndex++) {
        NSDictionary* program = [programs objectAtIndex:programIndex];
        [self _executeRivenProgram:[[program objectForKey:RXScriptProgramKey] bytes]
                             count:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
    }
    
#if defined(DEBUG)
    [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

    // release the card if it no longer is executing programs
    if (_programExecutionDepth == 0) {
        [executing_card release];
        _current_hotspot = nil;
        
        // if the card hid the mouse cursor while executing programs, we can now show it again
        if (_did_hide_mouse) {
            [controller showMouseCursor];
            _did_hide_mouse = NO;
        }
    }
    
    // we need to enable hotspot handling at the end of mouse up messages
    [controller enableHotspotHandling];
}

#pragma mark -
#pragma mark movie playback

- (void)_handleBlockingMovieFinishedPlaying:(NSNotification*)notification {
    // WARNING: MUST RUN ON MAIN THREAD
    [[NSNotificationCenter defaultCenter] removeObserver:self name:RXMoviePlaybackDidEndNotification object:[notification object]];
        
    // signal the movie playback semaphore to unblock the script thread
    semaphore_signal(_moviePlaybackSemaphore);
}

- (void)_resetMovie:(RXMovie*)movie {
    // WARNING: MUST RUN ON MAIN THREAD
    
    // the movie could be enabled (the bspit 279 book shows this), in which
    // case we need to defer the reset until the movie is played or enabled
    if ([controller isMovieEnabled:movie]) {
#if defined(DEBUG)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@deferring reset of movie %@ because it is enabled", logPrefix, movie);
#endif
        [_movies_to_reset addObject:movie];
    } else
        [movie reset];
}

- (void)_playMovie:(RXMovie*)movie {
    // WARNING: MUST RUN ON MAIN THREAD
    
    // if the movie is scheduled for reset, do the reset now
    if ([_movies_to_reset containsObject:movie]) {
        [movie reset];
        [_movies_to_reset removeObject:movie];
    }
    
    [movie play];
}

- (void)_playBlockingMovie:(RXMovie*)movie {
    // WARNING: MUST RUN ON MAIN THREAD
    
    // register for rate notifications on the blocking movie handler
    // FIXME: remove exposed movie proxy implementation detail
    if ([movie isKindOfClass:[RXMovieProxy class]])
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleBlockingMovieFinishedPlaying:)
                                                     name:RXMoviePlaybackDidEndNotification
                                                   object:[(RXMovieProxy*)movie proxiedMovie]];
    else
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleBlockingMovieFinishedPlaying:)
                                                     name:RXMoviePlaybackDidEndNotification
                                                   object:movie];
    
    // hide the mouse cursor
    if (!_did_hide_mouse) {
        _did_hide_mouse = YES;
        [controller hideMouseCursor];
    }
    
    // if the movie is scheduled for reset, do the reset now
    if ([_movies_to_reset containsObject:movie]) {
        [movie reset];
        [_movies_to_reset removeObject:movie];
    }
    
    // disable looping to make sure we don't deadlock by never finishing playback
    [movie setLooping:NO];
    
    // start playing the movie
    [movie setRate:1.0f];
}

- (void)_stopMovie:(RXMovie*)movie {
    // WARNING: MUST RUN ON MAIN THREAD
    [movie stop];
}

- (void)_muteMovie:(RXMovie*)movie {
    // WARNING: MUST RUN ON MAIN THREAD
    [movie setVolume:0.0f];
}

- (void)_unmuteMovie:(RXMovie*)movie {
    // WARNING: MUST RUN ON MAIN THREAD
    // FIXME: remove exposed movie proxy implementation detail
    [(RXMovieProxy*)movie restoreMovieVolume];
}

- (void)_collectMovies:(NSTimer*)timer {
    // iterate through the code2movie map and unload any movie that's not active
    // FIXME: implement the movie collector
}

#pragma mark -
#pragma mark dynamic pictures

- (void)_drawPictureWithID:(uint16_t)ID archive:(MHKArchive*)archive displayRect:(NSRect)display_rect samplingRect:(NSRect)sampling_rect {
    // get the resource descriptor for the tBMP resource
    NSError* error;
    NSDictionary* picture_descriptor = [archive bitmapDescriptorWithID:ID error:&error];
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
    
    // compute the size of the buffer needed to store the texture; we'll be using
    // MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED as the texture format, which is 4 bytes per pixel
    GLsizeiptr picture_size = picture_width * picture_height * 4;
    
    // check if we have a cache for the tBMP ID; create a dynamic picture structure otherwise and map it to the tBMP ID
    uintptr_t dynamic_picture_key = ID;
    struct rx_card_dynamic_picture* dynamic_picture = (struct rx_card_dynamic_picture*)NSMapGet(_dynamicPictureMap,
                                                                                                (const void*)dynamic_picture_key);
    if (dynamic_picture == NULL) {
        dynamic_picture = (struct rx_card_dynamic_picture*)malloc(sizeof(struct rx_card_dynamic_picture*));
        
        // get the load context and lock it
        CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
        CGLLockContext(cgl_ctx);
        
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, [RXDynamicPicture sharedDynamicPictureUnpackBuffer]); glReportError();
        GLvoid* picture_buffer = glMapBuffer(GL_PIXEL_UNPACK_BUFFER, GL_WRITE_ONLY); glReportError();
        
        // load the picture in the mapped picture buffer
        if (![archive loadBitmapWithID:ID buffer:picture_buffer format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED error:&error])
            @throw [NSException exceptionWithName:@"RXPictureLoadException"
                                           reason:@"Could not load a picture resource."
                                         userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
        
        // unmap the unpack buffer
        if (GLEE_APPLE_flush_buffer_range)
            glFlushMappedBufferRangeAPPLE(GL_PIXEL_UNPACK_BUFFER, 0, picture_size);
        glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER); glReportError();
        
        // create a texture object and bind it
        glGenTextures(1, &dynamic_picture->texture); glReportError();
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, dynamic_picture->texture); glReportError();
        
        // texture parameters
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glReportError();
        
        // client storage is not compatible with PBO texture unpack
        glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_FALSE);
        
        // unpack the texture
        glTexImage2D(GL_TEXTURE_RECTANGLE_ARB,
                     0,
                     GL_RGBA8,
                     picture_width, picture_height,
                     0,
                     GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV,
                     BUFFER_OFFSET((void*)NULL, 0)); glReportError();
        
        // reset the unpack buffer state and re-enable client storage
        glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE); glReportError();
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0); glReportError();
        
        // we created a new texture object, so flush
        glFlush();
        
        // unlock the load context
        CGLUnlockContext(cgl_ctx);
        
        // map the tBMP ID to the dynamic picture
        NSMapInsert(_dynamicPictureMap, (void*)dynamic_picture_key, dynamic_picture);
    }
    
    // create a RXDynamicPicture object and queue it for rendering
    RXDynamicPicture* picture = [[RXDynamicPicture alloc] initWithTexture:dynamic_picture->texture
                                                             samplingRect:sampling_rect
                                                               renderRect:display_rect
                                                                    owner:self];
    [controller queuePicture:picture];
    [picture release];
    
    // swap the render state; this always marks the back render state as modified
    [self _updateScreen];
}

- (void)_drawPictureWithID:(uint16_t)ID stack:(RXStack*)stack displayRect:(NSRect)display_rect samplingRect:(NSRect)sampling_rect {
    MHKArchive* archive = [[stack fileWithResourceType:@"tBMP" ID:ID] archive];
    [self _drawPictureWithID:ID archive:archive displayRect:display_rect samplingRect:sampling_rect];
}

#pragma mark -
#pragma mark sound playback

- (void)_playDataSoundWithID:(uint16_t)ID gain:(float)gain duration:(double*)duration_ptr {
    RXDataSound* sound = [RXDataSound new];
    sound->parent = [[card descriptor] parent];
    sound->ID = ID;
    sound->gain = gain;
    sound->pan = 0.5f;
    
    [controller playDataSound:sound];
    
    if (duration_ptr)
        *duration_ptr = sound->source->Duration();
    [sound release];
}

#pragma mark -

- (void)_invalid_opcode:(const uint16_t)argc arguments:(const uint16_t*)argv {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"INVALID RIVEN SCRIPT OPCODE EXECUTED: %d", argv[-2]]
                                 userInfo:nil];
}

- (void)_opcode_unimplemented:(const uint16_t)argc arguments:(const uint16_t*)argv {
    uint16_t argi = 0;
    NSString* fmt_str = [NSString stringWithFormat:@"WARNING: opcode %hu not implemented, arguments: {", *(argv - 2)];
    if (argc > 1) {
        for (; argi < argc - 1; argi++)
            fmt_str = [fmt_str stringByAppendingFormat:@"%hu, ", argv[argi]];
    }
    
    if (argc > 0)
        fmt_str = [fmt_str stringByAppendingFormat:@"%hu", argv[argi]];
    
    fmt_str = [fmt_str stringByAppendingString:@"}"];
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@%@", logPrefix, fmt_str);
}

- (void)_opcode_noop:(const uint16_t)argc arguments:(const uint16_t*)argv {

}

// 1
- (void)_opcode_drawDynamicPicture:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 9)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
    
    NSRect display_rect = RXMakeCompositeDisplayRect(argv[1], argv[2], argv[3], argv[4]);
    NSRect sampling_rect = NSMakeRect(argv[5], argv[6], argv[7] - argv[5], argv[8] - argv[6]);
    
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@drawing dynamic picture ID %hu in rect {{%f, %f}, {%f, %f}}", 
            logPrefix, argv[0], display_rect.origin.x, display_rect.origin.y, display_rect.size.width, display_rect.size.height);
#endif
    
    [self _drawPictureWithID:argv[0] stack:[card parent] displayRect:display_rect samplingRect:sampling_rect];
}

// 2
- (void)_opcode_goToCard:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@going to card ID %hu", logPrefix, argv[0]);
#endif

    RXStack* parent = [[card descriptor] parent];
    [controller setActiveCardWithStack:[parent key] ID:argv[0] waitUntilDone:YES];
}

// 3
- (void)_opcode_activateSynthesizedSLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling a synthesized slst record", logPrefix);
#endif

    RXSoundGroup* oldSoundGroup = _synthesizedSoundGroup;

    // argv + 1 is suitable for _createSoundGroupWithSLSTRecord
    uint16_t soundCount = argv[0];
    _synthesizedSoundGroup = [card createSoundGroupWithSLSTRecord:(argv + 1) soundCount:soundCount swapBytes:NO];
    
    [controller activateSoundGroup:_synthesizedSoundGroup];
    _did_activate_slst = YES;
    
    [oldSoundGroup release];
}

// 4
- (void)_opcode_playDataSound:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 3)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@playing local sound resource id=%hu, volume=%hu, blocking=%hu",
            logPrefix, argv[0], argv[1], argv[2]);
#endif
    
    double duration;
    [self _playDataSoundWithID:argv[0] gain:(float)argv[1] / kRXSoundGainDivisor duration:&duration];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    
    // argv[2] is a "wait for sound" boolean
    if (argv[2]) {
        // hide the mouse cursor
        if (!_did_hide_mouse) {
            _did_hide_mouse = YES;
            [controller hideMouseCursor];
        }
        
        // sleep for the duration minus the time that has elapsed since we started the sound
        usleep((duration - (CFAbsoluteTimeGetCurrent() - now)) * 1E6);
    }
}

// 5
- (void)_opcode_activateSynthesizedMLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 10)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
    
    // there's always going to be something before argv, so doing the -1 offset here is fine
    struct rx_mlst_record* mlst_r = (struct rx_mlst_record*)(argv - 1);

#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating synthesized MLST [movie_id=%hu, code=%hu]",
            logPrefix, mlst_r->movie_id, mlst_r->code);
#endif
    
    // have the card load the movie
    RXMovie* movie = [card loadMovieWithMLSTRecord:mlst_r];
    
    // update the code to movie map
    uintptr_t k = mlst_r->code;
    NSMapInsert(code2movieMap, (const void*)k, movie);
    
    // reset the movie
    [self performSelectorOnMainThread:@selector(_resetMovie:) withObject:movie waitUntilDone:YES];
    
    // should re-apply the MLST settings to the movie here, but because of the way RX is setup, we don't need to do that
    // in particular, _resetMovie will reset the movie back to the beginning and invalidate any decoded frame it may have
}

// 7
- (void)_opcode_setVariable:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 2)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
    
    RXStack* parent = [[card descriptor] parent];
    NSString* name = [parent varNameAtIndex:argv[0]];
    if (!name)
        name = [NSString stringWithFormat:@"%@%hu", [parent key], argv[0]];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@setting variable %@ to %hu", logPrefix, name, argv[1]);
#endif
    
    [[g_world gameState] setUnsignedShort:argv[1] forKey:name];
}

// 9
- (void)_opcode_enableHotspot:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling hotspot %hu", logPrefix, argv[0]);
#endif
    
    uintptr_t k = argv[0];
    RXHotspot* hotspot = (RXHotspot*)NSMapGet([card hotspotsIDMap], (void*)k);
    assert(hotspot);
    
    if (!hotspot->enabled) {
        hotspot->enabled = YES;
        
        OSSpinLockLock(&_activeHotspotsLock);
        [_activeHotspots addObject:hotspot];
        [_activeHotspots sortUsingSelector:@selector(compareByIndex:)];
        OSSpinLockUnlock(&_activeHotspotsLock);
        
        // instruct the script handler to update the hotspot state
        [controller updateHotspotState];
    }
}

// 10
- (void)_opcode_disableHotspot:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling hotspot %hu", logPrefix, argv[0]);
#endif
    
    uintptr_t k = argv[0];
    RXHotspot* hotspot = (RXHotspot*)NSMapGet([card hotspotsIDMap], (void*)k);
    assert(hotspot);
    
    if (hotspot->enabled) {
        hotspot->enabled = NO;
        
        OSSpinLockLock(&_activeHotspotsLock);
        [_activeHotspots removeObject:hotspot];
        [_activeHotspots sortUsingSelector:@selector(compareByIndex:)];
        OSSpinLockUnlock(&_activeHotspotsLock);
        
        // instruct the script handler to update the hotspot state
        [controller updateHotspotState];
    }
}

// 12
- (void)_opcode_clearSounds:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
    
    uint16_t options = argv[0];
    
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@clearing sounds with options %hu", logPrefix, options);
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
- (void)_opcode_setCursor:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@setting cursor to %hu", logPrefix, argv[0]);
#endif
    
    [controller setMouseCursor:argv[0]];
}

// 14
- (void)_opcode_pause:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@pausing for %d msec", logPrefix, argv[0]);
#endif
    
    // in case the pause delay is 0, just return immediatly
    if (argv[0] == 0)
        return;
    
    // hide the mouse cursor
    if (!_did_hide_mouse) {
        _did_hide_mouse = YES;
        [controller hideMouseCursor];
    }
    
    // sleep for the specified amount of ms
    usleep(argv[0] * 1000);
}

// 17
- (void)_opcode_callExternal:(const uint16_t)argc arguments:(const uint16_t*)argv {
    uint16_t argi = 0;
    uint16_t external_id = argv[0];
    uint16_t external_argc = argv[1];
    
    NSString* external_name = [[[[card descriptor] parent] externalNameAtIndex:external_id] lowercaseString];
    if (!external_name)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID EXTERNAL COMMAND ID" userInfo:nil];
    
#if defined(DEBUG)
    NSString* fmt = [NSString stringWithFormat:@"calling external %@(", external_name];
    
    if (external_argc > 1) {
        for (; argi < external_argc - 1; argi++)
            fmt = [fmt stringByAppendingFormat:@"%hu, ", argv[2 + argi]];
    }
    
    if (external_argc > 0)
        fmt = [fmt stringByAppendingFormat:@"%hu", argv[2 + argi]];
    
    fmt = [fmt stringByAppendingString:@") {"];
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@%@", logPrefix, fmt);
    
    // augment script log indentation for the external command
    [logPrefix appendString:@"    "];
#endif
    
    // dispatch the call to the external command
    rx_command_dispatch_entry_t* command_dispatch = (rx_command_dispatch_entry_t*)NSMapGet(_riven_external_command_dispatch_map,
                                                                                           external_name);
    if (!command_dispatch) {
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@    WARNING: external command '%@' is not implemented!",
                logPrefix, external_name);
#if defined(DEBUG)
        [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
        return;
    }
        
    command_dispatch->imp(self, command_dispatch->sel, external_argc, argv + 2);
    
#if defined(DEBUG)
    [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
}

// 18
- (void)_opcode_scheduleTransition:(const uint16_t)argc arguments:(const uint16_t*)argv {
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
        RXOLog2(kRXLoggingScript, kRXLoggingLevelMessage, @"%@scheduling transition %@", logPrefix, transition);
#endif
    
    // queue the transition
    // FIXME: need to review this dropping mechanism and see if we could just clear the transition queue at certain points
    if (transition->type == RXTransitionDissolve && (_previous_opcodes[0] == 18 || _previous_opcodes[1] == 18) && _queuedAPushTransition)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelMessage, @"WARNING: dropping dissolve transition because of recently scheduled push transition");
    else
        [controller queueTransition:transition];
    
    // transition is now owned by the transitionq queue
    [transition release];
    
    // leave a note if we queued a push transition
    if (transition->type == RXTransitionSlide)
        _queuedAPushTransition = YES;
    else
        _queuedAPushTransition = NO;    
}

// 19
- (void)_opcode_reloadCard:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@reloading card", logPrefix);
#endif
    
    // this command reloads whatever is the current card
    RXSimpleCardDescriptor* current_card = [[g_world gameState] currentCard];
    [controller setActiveCardWithStack:current_card->stackKey ID:current_card->cardID waitUntilDone:YES];
}

// 20
- (void)_opcode_disableScreenUpdates:(const uint16_t)argc arguments:(const uint16_t*)argv {
    _screen_update_disable_counter++;
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling screen updates (%d)", logPrefix, _screen_update_disable_counter);
#endif
}

// 21
- (void)_opcode_enableScreenUpdates:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (_screen_update_disable_counter > 0)
        _screen_update_disable_counter--;
    
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling screen updates (%d)", logPrefix, _screen_update_disable_counter);
#endif
    
    // this command also triggers a screen update (which may be dropped if the counter is still not 0)
    [self _updateScreen];
}

// 24
- (void)_opcode_incrementVariable:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 2)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
    
    RXStack* parent = [[card descriptor] parent];
    NSString* name = [parent varNameAtIndex:argv[0]];
    if (!name)
        name = [NSString stringWithFormat:@"%@%hu", [parent key], argv[0]];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@incrementing variable %@ by %hu", logPrefix, name, argv[1]);
#endif
    
    uint16_t v = [[g_world gameState] unsignedShortForKey:name];
    [[g_world gameState] setUnsignedShort:(v + argv[1]) forKey:name];
}

// 25
- (void)_opcode_decrementVariable:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 2)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
    
    RXStack* parent = [[card descriptor] parent];
    NSString* name = [parent varNameAtIndex:argv[0]];
    if (!name)
        name = [NSString stringWithFormat:@"%@%hu", [parent key], argv[0]];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@decrementing variable %@ by %hu", logPrefix, name, argv[1]);
#endif
    
    uint16_t v = [[g_world gameState] unsignedShortForKey:name];
    [[g_world gameState] setUnsignedShort:(v - argv[1]) forKey:name];
}

// 26
- (void)_opcode_closeAllMovies:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@closing all movies", logPrefix);
#endif
}

// 27
- (void)_opcode_goToStack:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 3)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
    
    // get the stack for the given stack key
    NSString* stackKey = [[[card descriptor] parent] stackNameAtIndex:argv[0]];
    RXStack* stack = [[RXEditionManager sharedEditionManager] loadStackWithKey:stackKey];
    if (!stack) {
        _abortProgramExecution = YES;
        return;
    }
    
    uint32_t card_rmap = (argv[1] << 16) | argv[2];
    uint16_t card_id = [stack cardIDFromRMAPCode:card_rmap];
    
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@going to stack %@ on card ID %hu", logPrefix, stackKey, card_id);
#endif
    
    [controller setActiveCardWithStack:stackKey ID:card_id waitUntilDone:YES];
}

// 28
- (void)_opcode_disableMovie:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
    
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling movie with code %hu", logPrefix, argv[0]);
#endif
    
    // get the movie object
    uintptr_t k = argv[0];
    RXMovie* movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)k);
    
    // it is legal to disable a code that has no movie associated with it
    if (!movie)
        return;
    
    // disable the movie in the renderer
    [controller disableMovie:movie];
}

// 29
- (void)_opcode_disableAllMovies:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
    
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling all movies", logPrefix);
#endif
    
    // disable all movies in the renderer
    [controller disableAllMovies];
}

// 31
- (void)_opcode_enableMovie:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling movie with code %hu", logPrefix, argv[0]);
#endif
    
    // get the movie object
    uintptr_t k = argv[0];
    RXMovie* movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)k);
    
    // it is legal to disable a code that has no movie associated with it
    if (!movie)
        return;
    
    // if the movie is scheduled for reset, do the reset now
    if ([_movies_to_reset containsObject:movie]) {
        [self performSelectorOnMainThread:@selector(_resetMovie:) withObject:movie waitUntilDone:YES];
        [_movies_to_reset removeObject:movie];
    }
    
    // enable the movie in the renderer
    [controller enableMovie:movie];
}

// 32
- (void)_opcode_startMovieAndWaitUntilDone:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
    
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@starting movie with code %hu and waiting until done", logPrefix, argv[0]);
#endif
    
    // get the movie object
    uintptr_t k = argv[0];
    RXMovie* movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)k);
    
    // it is legal to play a code that has no movie associated with it; it's a no-op
    if (!movie)
        return;
    
    // start the movie and register for rate change notifications
    [self performSelectorOnMainThread:@selector(_playBlockingMovie:) withObject:movie waitUntilDone:YES];
    
    // enable the movie in the renderer
    [controller enableMovie:movie];
    
    // wait until the movie is done playing
    semaphore_wait(_moviePlaybackSemaphore);
}

// 33
- (void)_opcode_startMovie:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@starting movie with code %hu", logPrefix, argv[0]);
#endif
    
    // get the movie object
    uintptr_t k = argv[0];
    RXMovie* movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)k);

    // it is legal to play a code that has no movie associated with it; it's a no-op
    if (!movie)
        return;
    
    // start the movie and block until done
    [self performSelectorOnMainThread:@selector(_playMovie:) withObject:movie waitUntilDone:YES];
    
    // enable the movie in the renderer
    [controller enableMovie:movie];
}

// 34
- (void)_opcode_stopMovie:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@stopping movie with code %hu", logPrefix, argv[0]);
#endif
    
    // get the movie object
    uintptr_t k = argv[0];
    RXMovie* movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)k);

    // it is legal to stop a code that has no movie associated with it; it's a no-op
    if (!movie)
        return;
    
    // stop the movie and block until done
    [self performSelectorOnMainThread:@selector(_stopMovie:) withObject:movie waitUntilDone:YES];
}

// 37
- (void)_opcode_fadeAmbientSounds:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@fading out ambient sounds", logPrefix, argv[0]);
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
- (void)_opcode_complexStartMovie:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 5)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
    
    uint32_t delay = (argv[1] << 16) | argv[2];
    uint16_t movie_code = argv[0];
    uint16_t delayed_command = argv[3];
    uint16_t delayed_command_arg = argv[4];
    
#if defined(DEBUG)
    if (!_disableScriptLogging) {
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@starting movie with code %hu, waiting %u ms, and executing command %d with argument %d {",
            logPrefix, movie_code, delay, delayed_command, delayed_command_arg);
        [logPrefix appendString:@"    "];
    }
#endif
    
    // play the movie
    [self _opcode_startMovie:1 arguments:&movie_code];
    
    // wait the specified delay
    if (delay > 0) {
        // hide the mouse cursor
        if (!_did_hide_mouse) {
            _did_hide_mouse = YES;
            [controller hideMouseCursor];
        }
        
        // sleep for the specified amount of ms
        if (delay > 0)
            usleep(delay * 1000);
    }
    
    // execute the delayed command
    DISPATCH_COMMAND1(delayed_command, delayed_command_arg);
    
#if defined(DEBUG)
    if (!_disableScriptLogging) {
        [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
    }
#endif
}

// 39
- (void)_opcode_activatePLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating plst record at index %hu", logPrefix, argv[0]);
#endif
    
    // create an RXPicture for the PLST record and queue it for rendering
    GLuint index = argv[0] - 1;
    RXPicture* picture = [[RXPicture alloc] initWithTexture:[card pictureTextures][index]
                                                        vao:[card pictureVAO]
                                                      index:4 * index
                                                      owner:self];
    [controller queuePicture:picture];
    [picture release];
    
    // opcode 39 triggers a render state swap
    [self _updateScreen];
    
    // indicate that an PLST record has been activated (to manage the automatic activation of PLST record 1 if none has been)
    _did_activate_plst = YES;
}

// 40
- (void)_opcode_activateSLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating slst record at index %hu", logPrefix, argv[0]);
#endif
    
    // the script handler is responsible for this
    [controller activateSoundGroup:[[card soundGroups] objectAtIndex:argv[0] - 1]];
    _did_activate_slst = YES;
}

// 41
- (void)_opcode_activateMLSTAndStartMovie:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
    
    uint16_t code = [card movieCodes][argv[0] - 1];
    
#if defined(DEBUG)
    if (!_disableScriptLogging) {
        RXOLog2(kRXLoggingScript, kRXLoggingLevelMessage, @"%@activating mlst record %hu [code=%hu] and starting movie {", logPrefix, argv[0], code);
        [logPrefix appendString:@"    "];
    }
#endif
    
    DISPATCH_COMMAND2(RX_COMMAND_ACTIVATE_MLST, argv[0], 0);
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE, code);
    
#if defined(DEBUG)
    if (!_disableScriptLogging) {
        [logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
    }
#endif
}

// 43
- (void)_opcode_activateBLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating blst record at index %hu", logPrefix, argv[0]);
#endif
    
    struct rx_blst_record* record = [card hotspotControlRecords] + (argv[0] - 1);
    uintptr_t k =  record->hotspot_id;
    RXHotspot* hotspot = (RXHotspot*)NSMapGet([card hotspotsIDMap], (void*)k);
    assert(hotspot);
    
    OSSpinLockLock(&_activeHotspotsLock);
    if (record->enabled == 1 && !hotspot->enabled)
        [_activeHotspots addObject:hotspot];
    else if (record->enabled == 0 && hotspot->enabled)
        [_activeHotspots removeObject:hotspot];
    OSSpinLockUnlock(&_activeHotspotsLock);
    
    hotspot->enabled = record->enabled;
    
    OSSpinLockLock(&_activeHotspotsLock);
    [_activeHotspots sortUsingSelector:@selector(compareByIndex:)];
    OSSpinLockUnlock(&_activeHotspotsLock);
    
    // instruct the script handler to update the hotspot state
    [controller updateHotspotState];
}

// 44
- (void)_opcode_activateFLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating flst record at index %hu", logPrefix, argv[0]);
#endif

    [controller queueSpecialEffect:[card sfxes] + (argv[0] - 1) owner:card];
}

// 46
- (void)_opcode_activateMLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 1)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
    uintptr_t k = [card movieCodes][argv[0] - 1];

#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating mlst record %hu [code=%hu]", logPrefix, argv[0], k);
#endif
    
    // update the code to movie map
    RXMovie* movie = [[card movies] objectAtIndex:argv[0] - 1];
    NSMapInsert(code2movieMap, (const void*)k, movie);
    
    // reset the movie
    [self performSelectorOnMainThread:@selector(_resetMovie:) withObject:movie waitUntilDone:YES];
    
    // should re-apply the MLST settings to the movie here, but because of the way RX is setup, we don't need to do that
    // in particular, _resetMovie will reset the movie back to the beginning and invalidate any decoded frame it may have
}

// 47
- (void)_opcode_activateSLSTWithVolume:(const uint16_t)argc arguments:(const uint16_t*)argv {
    if (argc < 2)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating slst record at index %hu and overriding volunme to %hu",
            logPrefix, argv[0], argv[1]);
#endif
    
    // get the sound group
    RXSoundGroup* sg = [[card soundGroups] objectAtIndex:argv[0] - 1];
    
    // temporarily change its gain
    uint16_t integer_gain = argv[1];
    float gain = (float)integer_gain / kRXSoundGainDivisor;
    float original_gain = sg->gain;
    sg->gain = gain;
    
    // activate the sound group
    [controller activateSoundGroup:sg];
    _did_activate_slst = YES;
    
    // restore its original gain
    sg->gain = original_gain;
}

#pragma mark -
#pragma mark main menu

DEFINE_COMMAND(xarestoregame) {
    [[NSApp delegate] performSelectorOnMainThread:@selector(openDocument:) withObject:self waitUntilDone:NO];
}

DEFINE_COMMAND(xasetupcomplete) {
    // schedule a fade transition
    DISPATCH_COMMAND1(RX_COMMAND_SCHEDULE_TRANSITION, 16);
    
    // clear the ambient sound
    DISPATCH_COMMAND1(RX_COMMAND_CLEAR_SLST, 0);
    
    // go to card 1
    DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, 1);
}

#pragma mark -
#pragma mark inventory

DEFINE_COMMAND(xthideinventory) {
    // nothing to do in Riven X for this really
}

#pragma mark -
#pragma mark shared journal support

- (void)_returnFromJournal {
    // schedule a cross-fade transition to the return card
    RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionDissolve
                                                        direction:0
                                                           region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
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

#pragma mark -
#pragma mark atrus journal

- (void)_updateAtrusJournal {
    uint16_t page = [[g_world gameState] unsignedShortForKey:@"aatruspage"];
    assert(page > 0);
    
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

DEFINE_COMMAND(xaatrusopenbook) {
    [self _updateAtrusJournal];
}

DEFINE_COMMAND(xaatrusbookback) {
    [self _returnFromJournal];
}

DEFINE_COMMAND(xaatrusbookprevpage) {
    uint16_t page = [[g_world gameState] unsignedShortForKey:@"aatruspage"];
    assert(page > 1);
    [[g_world gameState] setUnsignedShort:page - 1 forKey:@"aatruspage"];
    
    if (page == 2)
        DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 8, 256, 0);
    else
        DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 3, 256, 0);
    
    RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide
                                                        direction:RXTransitionRight
                                                           region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
    [controller queueTransition:transition];
    [transition release];
    
    DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
}

DEFINE_COMMAND(xaatrusbooknextpage) {
    uint16_t page = [[g_world gameState] unsignedShortForKey:@"aatruspage"];
    if (page < 10) {
        [[g_world gameState] setUnsignedShort:page + 1 forKey:@"aatruspage"];
        
        if (page == 1)
            DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 8, 256, 0);
        else
            DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 5, 256, 0);
        
        RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide
                                                            direction:RXTransitionLeft
                                                               region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
        [controller queueTransition:transition];
        [transition release];
        
        DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
    }
}

#pragma mark -
#pragma mark catherine journal

- (void)_updateCatherineJournal {
    uint16_t page = [[g_world gameState] unsignedShortForKey:@"acathpage"];
    assert(page > 0);
    
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
    
    // draw the telescope combination
    // FIXME: actually generate a combination per game...
    if (page == 28) {
        NSPoint combination_display_origin = NSMakePoint(156.0f, 120.0f);
        NSPoint combination_sampling_origin = NSMakePoint(32.0f * 3, 0.0f);
        NSRect combination_base_rect = NSMakeRect(0.0f, 0.0f, 32.0f, 25.0f);
        
        [self _drawPictureWithID:13
                           stack:[card parent]
                     displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                    samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
        combination_display_origin.x += combination_base_rect.size.width;
        
        [self _drawPictureWithID:14
                           stack:[card parent]
                     displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                    samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
        combination_display_origin.x += combination_base_rect.size.width;
        
        [self _drawPictureWithID:15
                           stack:[card parent]
                     displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                    samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
        combination_display_origin.x += combination_base_rect.size.width;
        
        [self _drawPictureWithID:16
                           stack:[card parent]
                     displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                    samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
        combination_display_origin.x += combination_base_rect.size.width;
        
        [self _drawPictureWithID:17
                           stack:[card parent]
                     displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                    samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
    }
}

DEFINE_COMMAND(xacathopenbook) {
    [self _updateCatherineJournal];
}

DEFINE_COMMAND(xacathbookback) {    
    [self _returnFromJournal];
}

DEFINE_COMMAND(xacathbookprevpage) {
    uint16_t page = [[g_world gameState] unsignedShortForKey:@"acathpage"];
    assert(page > 1);
    [[g_world gameState] setUnsignedShort:page - 1 forKey:@"acathpage"];
    
    if (page == 2)
        DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 9, 256, 0);
    else
        DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 4, 256, 0);
    
    RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide
                                                        direction:RXTransitionBottom
                                                           region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
    [controller queueTransition:transition];
    [transition release];
    
    DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
}

DEFINE_COMMAND(xacathbooknextpage) {
    uint16_t page = [[g_world gameState] unsignedShortForKey:@"acathpage"];
    if (page < 49) {
        [[g_world gameState] setUnsignedShort:page + 1 forKey:@"acathpage"];
        
        if (page == 1)
            DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 9, 256, 0);
        else
            DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 6, 256, 0);
        
        RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide
                                                            direction:RXTransitionTop
                                                               region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
        [controller queueTransition:transition];
        [transition release];
        
        DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
    }
}

#pragma mark -
#pragma mark trap book

DEFINE_COMMAND(xtrapbookback) { 
    [self _returnFromJournal];
}

#pragma mark -
#pragma mark introduction sequence

DEFINE_COMMAND(xtatrusgivesbooks) {
    // FIXME: implement xtatrusgivesbooks
}

DEFINE_COMMAND(xtchotakesbook) {
    // FIXME: implement xtchotakesbook

    // WORKAROUND as a side-effect of this command, we'll silence the ambient
    // sound before the last introduction movie plays; a active SLST command
    // comes after the movie
    DISPATCH_COMMAND1(RX_COMMAND_CLEAR_SLST, 1);
}

#pragma mark -
#pragma mark lab journal

- (void)_updateLabJournal {
    uint16_t page = [[g_world gameState] unsignedShortForKey:@"blabpage"];
    assert(page > 0);
    
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
                           stack:[card parent]
                     displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                    samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
        combination_display_origin.x += combination_base_rect.size.width;
        combo_bit--;

        while (!(domecombo & (1 << combo_bit)))
            combo_bit--;
        combination_sampling_origin.x = 32.0f * (24 - combo_bit);       
        [self _drawPictureWithID:365
                           stack:[card parent]
                     displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                    samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
        combination_display_origin.x += combination_base_rect.size.width;
        combo_bit--;
        
        while (!(domecombo & (1 << combo_bit)))
            combo_bit--;
        combination_sampling_origin.x = 32.0f * (24 - combo_bit);
        [self _drawPictureWithID:366
                           stack:[card parent]
                     displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                    samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
        combination_display_origin.x += combination_base_rect.size.width;
        combo_bit--;
        
        while (!(domecombo & (1 << combo_bit)))
            combo_bit--;
        combination_sampling_origin.x = 32.0f * (24 - combo_bit);
        [self _drawPictureWithID:367
                           stack:[card parent]
                     displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                    samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
        combination_display_origin.x += combination_base_rect.size.width;
        combo_bit--;
        
        while (!(domecombo & (1 << combo_bit)))
            combo_bit--;
        combination_sampling_origin.x = 32.0f * (24 - combo_bit);
        [self _drawPictureWithID:368
                           stack:[card parent]
                     displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y)
                    samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
    }
}

DEFINE_COMMAND(xblabopenbook) {
    [self _updateLabJournal];
}

DEFINE_COMMAND(xblabbookprevpage) {
    uint16_t page = [[g_world gameState] unsignedShortForKey:@"blabpage"];
    assert(page > 1);
    [[g_world gameState] setUnsignedShort:page - 1 forKey:@"blabpage"];
    
    DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 22, 256, 0);
    
    RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide
                                                        direction:RXTransitionRight
                                                           region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
    [controller queueTransition:transition];
    [transition release];
    
    DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
}

DEFINE_COMMAND(xblabbooknextpage) {
    uint16_t page = [[g_world gameState] unsignedShortForKey:@"blabpage"];
    if (page < 22) {
        [[g_world gameState] setUnsignedShort:page + 1 forKey:@"blabpage"];
        
        DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 23, 256, 0);
        
        RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide
                                                            direction:RXTransitionLeft
                                                               region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
        [controller queueTransition:transition];
        [transition release];
        
        DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
    }
}

#pragma mark -
#pragma mark gehn journal

- (void)_updateGehnJournal {
    uint16_t page = [[g_world gameState] unsignedShortForKey:@"ogehnpage"];
    assert(page > 0);
        
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, page);
}

DEFINE_COMMAND(xogehnopenbook) {
    [self _updateGehnJournal];
}

DEFINE_COMMAND(xogehnbookprevpage) {
    uint16_t page = [[g_world gameState] unsignedShortForKey:@"ogehnpage"];
    if (page <= 1)
        return;
    
    [[g_world gameState] setUnsignedShort:page - 1 forKey:@"ogehnpage"];
    
    DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 12, 256, 0);
    
    RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide
                                                        direction:RXTransitionRight
                                                           region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
    [controller queueTransition:transition];
    [transition release];
    
    DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
}

DEFINE_COMMAND(xogehnbooknextpage) {
    uint16_t page = [[g_world gameState] unsignedShortForKey:@"ogehnpage"];
    if (page >= 13)
        return;

    [[g_world gameState] setUnsignedShort:page + 1 forKey:@"ogehnpage"];
    
    DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 13, 256, 0);
    
    RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide
                                                        direction:RXTransitionLeft
                                                           region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
    [controller queueTransition:transition];
    [transition release];
    
    DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
}

#pragma mark -
#pragma mark rebel icon puzzle

- (BOOL)_isIconDepressed:(uint16_t)index {
    uint32_t icon_bitfield = [[g_world gameState] unsigned32ForKey:@"jicons"];
    return (icon_bitfield & (1U << (index - 1))) ? YES : NO;
}

- (uint32_t)_countDepressedIcons {
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

DEFINE_COMMAND(xicon) {
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

DEFINE_COMMAND(xcheckicons) {
    // this command resets the icon puzzle when a 6th icon is pressed
    if ([self _countDepressedIcons] >= 5) {
        [[g_world gameState] setUnsigned32:0 forKey:@"jicons"];
        [[g_world gameState] setUnsigned32:0 forKey:@"jiconorder"];
        
        DISPATCH_COMMAND3(RX_COMMAND_PLAY_DATA_SOUND, 46, 256, 1);
    }
}

DEFINE_COMMAND(xtoggleicon) {
    // this command toggles the state of a particular icon for the rebel tunnel puzzle
    uint32_t icon_sequence = [[g_world gameState] unsigned32ForKey:@"jiconorder"];
    uint32_t correct_icon_sequence = [[g_world gameState] unsigned32ForKey:@"jiconcorrectorder"];
    uint32_t icon_bitfield = [[g_world gameState] unsigned32ForKey:@"jicons"];
    uint32_t icon_bit = 1U << (argv[0] - 1);
    
    if (icon_bitfield & icon_bit) {
        [[g_world gameState] setUnsigned32:(icon_bitfield & ~icon_bit) forKey:@"jicons"];
        icon_sequence >>= 5;
    } else {
        [[g_world gameState] setUnsigned32:(icon_bitfield | icon_bit) forKey:@"jicons"];
        icon_sequence = icon_sequence << 5 | argv[0];
    }
    
    [[g_world gameState] setUnsigned32:icon_sequence forKey:@"jiconorder"];
    
    if (icon_sequence == correct_icon_sequence)
        [[g_world gameState] setUnsignedShort:1 forKey:@"jrbook"];
}

DEFINE_COMMAND(xjtunnel103_pictfix) {
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

DEFINE_COMMAND(xjtunnel104_pictfix) {
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

DEFINE_COMMAND(xjtunnel105_pictfix) {
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

DEFINE_COMMAND(xjtunnel106_pictfix) {
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


DEFINE_COMMAND(xreseticons) {
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@xreseticons was called, resetting the entire rebel icon puzzle state", logPrefix);
#endif

    [[g_world gameState] setUnsigned32:0 forKey:@"jiconorder"];
    [[g_world gameState] setUnsigned32:0 forKey:@"jicons"];
    [[g_world gameState] setUnsignedShort:0 forKey:@"jrbook"];
}

#pragma mark -
#pragma mark jungle elevator

- (void)_handleJungleElevatorMouth {
    // if the mouth is open, we need to close it before going up or down
    if ([[g_world gameState] unsignedShortForKey:@"jwmouth"]) {
        [[g_world gameState] setUnsignedShort:0 forKey:@"jwmouth"];
        
        // play the close mouth movie
        DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 3);
        
        // play the mouth control lever movie
        DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 8);
    }
}

static const float k_jungle_elevator_trigger_magnitude = 16.0f;

DEFINE_COMMAND(xhandlecontrolup) {
    NSRect mouse_vector = [controller mouseVector];
    [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];
    
    // track the mouse until the mouse button is released
    while ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                    beforeDate:[NSDate dateWithTimeIntervalSinceNow:k_mouse_tracking_loop_period]] &&
           isfinite(mouse_vector.size.width))
    {
        if (mouse_vector.size.height < 0.0f && fabsf(mouse_vector.size.height) >= k_jungle_elevator_trigger_magnitude) {
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
            [controller setActiveCardWithSimpleDescriptor:[[RXEditionManager sharedEditionManager] lookupCardWithKey:@"jungle elevator middle"]
                                            waitUntilDone:YES];
            
            // we're all done
            break;
        }
        
        [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];
        mouse_vector = [controller mouseVector];
    }
}

DEFINE_COMMAND(xhandlecontrolmid) {
    NSRect mouse_vector = [controller mouseVector];
    [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];
    
    // track the mouse until the mouse button is released
    while ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                    beforeDate:[NSDate dateWithTimeIntervalSinceNow:k_mouse_tracking_loop_period]] &&
           isfinite(mouse_vector.size.width))
    {
        if (mouse_vector.size.height >= k_jungle_elevator_trigger_magnitude) {
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
            [controller setActiveCardWithSimpleDescriptor:[[RXEditionManager sharedEditionManager] lookupCardWithKey:@"jungle elevator top"]
                                            waitUntilDone:YES];
            
            // we're all done
            break;
        } else if (mouse_vector.size.height < 0.0f && fabsf(mouse_vector.size.height) >= k_jungle_elevator_trigger_magnitude) {
            // play the switch down movie
            DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 6);
            
            [self _handleJungleElevatorMouth];
            
            // play the going down movie
            DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 4);
            
            // go to the bottom jungle elevator card
            [controller setActiveCardWithSimpleDescriptor:[[RXEditionManager sharedEditionManager] lookupCardWithKey:@"jungle elevator bottom"]
                                            waitUntilDone:YES];
            
            // we're all done
            break;
        }
        
        [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];
        mouse_vector = [controller mouseVector];
    }
}

DEFINE_COMMAND(xhandlecontroldown) {
    NSRect mouse_vector = [controller mouseVector];
    [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];
    
    // track the mouse until the mouse button is released
    while ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                    beforeDate:[NSDate dateWithTimeIntervalSinceNow:k_mouse_tracking_loop_period]] &&
           isfinite(mouse_vector.size.width))
    {
        if (mouse_vector.size.height >= k_jungle_elevator_trigger_magnitude) {
            // play the switch up movie
            DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 1);
            
            // play the going up movie
            DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);
            
            // go to the middle jungle elevator card
            [controller setActiveCardWithSimpleDescriptor:[[RXEditionManager sharedEditionManager] lookupCardWithKey:@"jungle elevator middle"]
                                            waitUntilDone:YES];
            
            // we're all done
            break;
        }
        
        [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];
        mouse_vector = [controller mouseVector];
    }
}

#pragma mark -
#pragma mark boiler central

DEFINE_COMMAND(xvalvecontrol) {
    uint16_t valve_state = [[g_world gameState] unsignedShortForKey:@"bvalve"];
    
    NSRect mouse_vector = [controller mouseVector];
    [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];
    
    // track the mouse until the mouse button is released
    while ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                    beforeDate:[NSDate dateWithTimeIntervalSinceNow:k_mouse_tracking_loop_period]] &&
           isfinite(mouse_vector.size.width))
    {
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

DEFINE_COMMAND(xbchipper) {
    [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];

    uint16_t valve_state = [[g_world gameState] unsignedShortForKey:@"bvalve"];
    if (valve_state != 2)
        return;
    
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);
}

DEFINE_COMMAND(xbupdateboiler) {
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

DEFINE_COMMAND(xbchangeboiler) {
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

DEFINE_COMMAND(xsoundplug) {
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

DEFINE_COMMAND(xjschool280_resetleft) {
    [[g_world gameState] setUnsignedShort:0 forKey:@"jleftpos"];
}

DEFINE_COMMAND(xjschool280_resetright) {
    [[g_world gameState] setUnsignedShort:0 forKey:@"jrightpos"];
}

- (void)_configureDoomedVillagerMovie:(NSNumber*)stepsNumber {
    uint16_t level_of_doom;
    uintptr_t k;
    if ([[g_world gameState] unsignedShortForKey:@"jwharkpos"] == 1) {
        level_of_doom = [[g_world gameState] unsignedShortForKey:@"jleftpos"];
        k = 3;
    } else {
        level_of_doom = [[g_world gameState] unsignedShortForKey:@"jrightpos"];
        k = 5;
    }
    
    RXMovie* movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)k);
    
    // compute the duration per tick
    QTTime duration = [movie duration];
    duration.timeValue /= 19;
    
    // set the movie's playback range
    QTTimeRange movie_range = QTMakeTimeRange(QTMakeTime(duration.timeValue * level_of_doom, duration.timeScale),
                                              QTMakeTime(duration.timeValue * [stepsNumber unsignedShortValue], duration.timeScale));
    [movie setPlaybackSelection:movie_range];
}

DEFINE_COMMAND(xschool280_playwhark) {
    // cache the game state object
    RXGameState* state = [g_world gameState];

    // generate a random number between 1 and 10
    uint16_t the_number = random() % 9 + 1;
#if defined(DEBUG)
    if (!_disableScriptLogging)
        RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@rolled a %hu", logPrefix, the_number);
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
    [self performSelectorOnMainThread:@selector(_configureDoomedVillagerMovie:)
                           withObject:[NSNumber numberWithUnsignedShort:the_number]
                        waitUntilDone:YES];
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
        DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
        
        [state setUnsignedShort:0 forKey:villager_position_variable];
    }
    
    // disable rotateleft and enable rotateright
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_BLST, blsts_to_activate[0]);
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_BLST, blsts_to_activate[1]);
}

#pragma mark -
#pragma mark common dome methods

- (void)handleVisorButtonPressForDome:(NSString*)dome {
    uint16_t dome_state = [[g_world gameState] unsignedShortForKey:dome];
    if (dome_state == 3) {
        uintptr_t k = 2;
        RXMovie* button_movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)k);
        [self performSelectorOnMainThread:@selector(_unmuteMovie:) withObject:button_movie waitUntilDone:NO];
        DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);
    }
}

- (void)checkDome:(NSString*)dome mutingVisorButtonMovie:(BOOL)mute_visor {
    // when was the mouse pressed?
    double mouse_ts_s = [controller mouseTimestamp];
    
    // when was the movie at the time?
    uintptr_t k = 1;
    RXMovie* movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)k);
    
    NSTimeInterval movie_position;
    QTGetTimeInterval([movie _noLockCurrentTime], &movie_position);
    double event_delay = RXTimingTimestampDelta(RXTimingNow(), RXTimingOffsetTimestamp(0, mouse_ts_s));
    
    NSTimeInterval duration;
    QTGetTimeInterval([movie duration], &duration);
    
    // get the button movie
    k = 2;
    RXMovie* button_movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)k);
    
    // did we hit the golden eye frame?
#if defined(DEBUG)
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@movie_position=%f, event_delay=%f, position-delay=%f",
        logPrefix, movie_position, event_delay, movie_position - event_delay);
#endif
    // if (time > 2780 || time < 200)
    if (movie_position >= 4.58) {
        [[g_world gameState] setUnsignedShort:1 forKey:@"domecheck"];
        
        // mute button movie if requested and start asynchronous playback of the visor button movie
        if (mute_visor)
            [self performSelectorOnMainThread:@selector(_muteMovie:) withObject:button_movie waitUntilDone:NO];
        DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE, 2);
    } else
        DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, 2);
}

- (void)drawSlidersForDome:(NSString*)dome minHotspotID:(uintptr_t)min_id {
    // cache the hotspots ID map
    NSMapTable* hotspots_map = [card hotspotsIDMap];
    uint16_t background = [[RXEditionManager sharedEditionManager] lookupBitmapWithKey:[dome stringByAppendingString:@" sliders background"]];
    uint16_t sliders = [[RXEditionManager sharedEditionManager] lookupBitmapWithKey:[dome stringByAppendingString:@" sliders"]];
        
    // begin a screen update transaction
    DISPATCH_COMMAND0(RX_COMMAND_DISABLE_SCREEN_UPDATES);
    
    // draw the background; 220 x 69 is the slider background dimension
    NSRect display_rect = RXMakeCompositeDisplayRect(dome_slider_background_position.x, dome_slider_background_position.y,
                                                     dome_slider_background_position.x + 220, dome_slider_background_position.y + 69);
    [self _drawPictureWithID:background stack:[card parent] displayRect:display_rect samplingRect:NSMakeRect(0.0f, 0.0f, 0.0f, 0.0f)];
    
    // draw the sliders
    uintptr_t k = 0;
    for (int i = 0; i < 5; i++) {
        while (k < 25 && !(sliders_state & (1 << (24 - k))))
            k++;
        
        RXHotspot* h = (RXHotspot*)NSMapGet(hotspots_map, (void*)(k + min_id));
        k++;
        
        rx_core_rect_t hotspot_rect = [h coreFrame];
        display_rect = RXMakeCompositeDisplayRectFromCoreRect(hotspot_rect);
        NSRect sampling_rect = NSMakeRect(hotspot_rect.left - dome_slider_background_position.x,
                                          hotspot_rect.top - dome_slider_background_position.y,
                                          display_rect.size.width,
                                          display_rect.size.height);
        [self _drawPictureWithID:sliders stack:[card parent] displayRect:display_rect samplingRect:sampling_rect];
    }
    
    // end the screen update transaction
    DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
}

- (void)resetSlidersForDome:(NSString*)dome {
    // cache the tic sound
    RXDataSound* tic_sound = [RXDataSound new];
    tic_sound->parent = [[card descriptor] parent];
    tic_sound->ID = [[RXEditionManager sharedEditionManager] lookupSoundWithKey:[dome stringByAppendingString:@" slider tic"]];
    tic_sound->gain = 1.0f;
    tic_sound->pan = 0.5f;
    
    // cache the minimum slider hotspot ID
    RXHotspot* min_hotspot = (RXHotspot*)NSMapGet([card hotspotsNameMap], @"s1");
    assert(min_hotspot);
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
        DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"resetsliders") ID]);
        DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"opendome") ID]);
    } else {
        DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"resetsliders") ID]);
        DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"opendome") ID]);
    }
    
    [tic_sound release];
}

- (RXHotspot*)domeSliderHotspotForDome:(NSString*)dome mousePosition:(NSPoint)mouse_position activeHotspot:(RXHotspot*)active_hotspot minHotspotID:(uintptr_t)min_id {
    // cache the hotspots ID map
    NSMapTable* hotspots_map = [card hotspotsIDMap];
    
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
            mouse_position.y = [hotspot worldFrame].origin.y;
        
        if (NSPointInRect(mouse_position, [hotspot worldFrame])) {
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
                        uintptr_t reverse_scan_limit = [hotspot ID] - min_id;
                        for (uintptr_t k2 = [active_hotspot ID] - 1 - min_id; k2 >= reverse_scan_limit; k2--) {
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

- (void)handleSliderDragForDome:(NSString*)dome {
    // cache the tic sound
    RXDataSound* tic_sound = [RXDataSound new];
    tic_sound->parent = [[card descriptor] parent];
    tic_sound->ID = [[RXEditionManager sharedEditionManager] lookupSoundWithKey:[dome stringByAppendingString:@" slider tic"]];
    tic_sound->gain = 1.0f;
    tic_sound->pan = 0.5f;
    
    // cache the minimum slider hotspot ID
    RXHotspot* min_hotspot = (RXHotspot*)NSMapGet([card hotspotsNameMap], @"s1");
    assert(min_hotspot);
    uintptr_t min_hotspot_id = [min_hotspot ID];
    
    // determine if the mouse was on one of the active slider hotspots when it was pressed; if not, we're done
    NSRect mouse_vector = [controller mouseVector];
    RXHotspot* active_hotspot = [self domeSliderHotspotForDome:dome
                                                 mousePosition:mouse_vector.origin
                                                 activeHotspot:nil
                                                  minHotspotID:min_hotspot_id];
    if (!active_hotspot || !active_hotspot->enabled)
        return;
    
    // set the cursor to the closed hand cursor
    [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];
    
    // track the mouse, updating the position of the slider as appropriate
    while ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                    beforeDate:[NSDate dateWithTimeIntervalSinceNow:k_mouse_tracking_loop_period]] &&
           isfinite(mouse_vector.size.width))
    {
        // where are we now?
        RXHotspot* hotspot = [self domeSliderHotspotForDome:dome
                                              mousePosition:NSOffsetRect(mouse_vector, mouse_vector.size.width,
                                                                         mouse_vector.size.height).origin
                                              activeHotspot:active_hotspot
                                               minHotspotID:min_hotspot_id];
        if (hotspot && hotspot != active_hotspot) {
            // play the tic sound
            [controller playDataSound:tic_sound];
            
            // disable the old and enable the new
            sliders_state = (sliders_state & ~(1 << (24 - ([active_hotspot ID] - min_hotspot_id)))) |
                            (1 << (24 - ([hotspot ID] - min_hotspot_id)));
            active_hotspot = hotspot;
            
            // draw the new slider state
            [self drawSlidersForDome:dome minHotspotID:min_hotspot_id];
        }
        
        // update the mouse cursor and vector
        [controller setMouseCursor:RX_CURSOR_CLOSED_HAND];
        mouse_vector = [controller mouseVector];
    }
    
    // check if the sliders match the dome configuration
    uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
    if (sliders_state == domecombo) {
        DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"resetsliders") ID]);
        DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"opendome") ID]);
    } else {
        DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"resetsliders") ID]);
        DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"opendome") ID]);
    }
    
    [tic_sound release];
}

- (void)handleMouseOverSliderForDome:(NSString*)dome {
    RXHotspot* min_hotspot = (RXHotspot*)NSMapGet([card hotspotsNameMap], @"s1");
    assert(min_hotspot);
    uintptr_t min_hotspot_id = [min_hotspot ID];
    
    RXHotspot* active_hotspot = [self domeSliderHotspotForDome:dome
                                                 mousePosition:[controller mouseVector].origin
                                                 activeHotspot:nil
                                                  minHotspotID:min_hotspot_id];
    if (active_hotspot)
        [controller setMouseCursor:RX_CURSOR_OPEN_HAND];
    else
        [controller setMouseCursor:RX_CURSOR_FORWARD];
}

#pragma mark -
#pragma mark bdome dome

DEFINE_COMMAND(xbscpbtn) {
    [self handleVisorButtonPressForDome:@"bdome"];
}

DEFINE_COMMAND(xbisland_domecheck) {
    [self checkDome:@"bdome" mutingVisorButtonMovie:NO];
}

DEFINE_COMMAND(xbisland190_opencard) {
    // check if the sliders match the dome configuration
    uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
    if (sliders_state == domecombo) {
        DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"resetsliders") ID]);
        DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"opendome") ID]);
    }
}

DEFINE_COMMAND(xbisland190_resetsliders) {
    dome_slider_background_position.x = 200;
    [self resetSlidersForDome:@"bdome"];
}

DEFINE_COMMAND(xbisland190_slidermd) {
    dome_slider_background_position.x = 200;
    [self handleSliderDragForDome:@"bdome"];
}

DEFINE_COMMAND(xbisland190_slidermw) {
    [self handleMouseOverSliderForDome:@"bdome"];
}

#pragma mark -
#pragma mark gdome dome

DEFINE_COMMAND(xgscpbtn) {
    [self handleVisorButtonPressForDome:@"gdome"];
}

DEFINE_COMMAND(xgisland1490_domecheck) {
    [self checkDome:@"gdome" mutingVisorButtonMovie:NO];
}

DEFINE_COMMAND(xgisland25_opencard) {
    // check if the sliders match the dome configuration
    uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
    if (sliders_state == domecombo) {
        DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"resetsliders") ID]);
        DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"opendome") ID]);
    }
}

DEFINE_COMMAND(xgisland25_resetsliders) {
    dome_slider_background_position.x = 200;
    [self resetSlidersForDome:@"gdome"];
}

DEFINE_COMMAND(xgisland25_slidermd) {
    dome_slider_background_position.x = 200;
    [self handleSliderDragForDome:@"gdome"];
}

DEFINE_COMMAND(xgisland25_slidermw) {
    [self handleMouseOverSliderForDome:@"gdome"];
}


#pragma mark -
#pragma mark jspit dome

DEFINE_COMMAND(xjscpbtn) {
    [self handleVisorButtonPressForDome:@"jdome"];
}

DEFINE_COMMAND(xjisland3500_domecheck) {
    [self checkDome:@"jdome" mutingVisorButtonMovie:YES];
}

DEFINE_COMMAND(xjdome25_resetsliders) {
    dome_slider_background_position.x = 200;
    [self resetSlidersForDome:@"jdome"];
}

DEFINE_COMMAND(xjdome25_slidermd) {
    dome_slider_background_position.x = 200;
    [self handleSliderDragForDome:@"jdome"];
}

DEFINE_COMMAND(xjdome25_slidermw) {
    [self handleMouseOverSliderForDome:@"jdome"];
}

#pragma mark -
#pragma mark pdome dome

DEFINE_COMMAND(xpscpbtn) {
    [self handleVisorButtonPressForDome:@"pdome"];
}

DEFINE_COMMAND(xpisland290_domecheck) {
    [self checkDome:@"pdome" mutingVisorButtonMovie:NO];
}

DEFINE_COMMAND(xpisland25_opencard) {
    // check if the sliders match the dome configuration
    uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
    if (sliders_state == domecombo) {
        DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"resetsliders") ID]);
        DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"opendome") ID]);
    }
}

DEFINE_COMMAND(xpisland25_resetsliders) {
    dome_slider_background_position.x = 198;
    [self resetSlidersForDome:@"pdome"];
}

DEFINE_COMMAND(xpisland25_slidermd) {
    dome_slider_background_position.x = 198;
    [self handleSliderDragForDome:@"pdome"];
}

DEFINE_COMMAND(xpisland25_slidermw) {
    [self handleMouseOverSliderForDome:@"pdome"];
}

#pragma mark -
#pragma mark tspit dome

DEFINE_COMMAND(xtscpbtn) {
    [self handleVisorButtonPressForDome:@"tdome"];
}

DEFINE_COMMAND(xtisland4990_domecheck) {
    [self checkDome:@"tdome" mutingVisorButtonMovie:NO];
}

DEFINE_COMMAND(xtisland5056_opencard) {
    // check if the sliders match the dome configuration
    uint32_t domecombo = [[g_world gameState] unsigned32ForKey:@"aDomeCombo"];
    if (sliders_state == domecombo) {
        DISPATCH_COMMAND1(RX_COMMAND_DISABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"resetsliders") ID]);
        DISPATCH_COMMAND1(RX_COMMAND_ENABLE_HOTSPOT, [(RXHotspot*)NSMapGet([card hotspotsNameMap], @"opendome") ID]);
    }
}

DEFINE_COMMAND(xtisland5056_resetsliders) {
    dome_slider_background_position.x = 200;
    [self resetSlidersForDome:@"tdome"];
}

DEFINE_COMMAND(xtisland5056_slidermd) {
    dome_slider_background_position.x = 200;
    [self handleSliderDragForDome:@"tdome"];
}

DEFINE_COMMAND(xtisland5056_slidermw) {
    [self handleMouseOverSliderForDome:@"tdome"];
}

#pragma mark -
#pragma mark power dome

typedef enum  {
    BLUE_MARBLE = 1,
    GREEN_MARBLE,
    ORANGE_MARBLE,
    PURPLE_MARBLE,
    RED_MARBLE,
    YELLOW_MARBLE
} rx_fire_marble_t;

static const uint32_t marble_offset_matrix[2][5] = {
    {134, 202, 270, 338, 406},  // x
    {24, 92, 159, 227, 295},    // y
};

static const uint32_t tiny_marble_offset_matrix[2][5] = {
    {246, 269, 293, 316, 340},  // x
    {263, 272, 284, 295, 309},  // y
};

static const uint32_t tiny_marble_receptable_position_vectors[2][6] = {
//   red    orange  yellow  green   blue    violet
    {376,   378,    380,    382,    384,    386},   // x
    {253,   257,    261,    265,    268,    273},   // y
};

static const float marble_size = 13.5f;

- (void)_drawTinyMarbleWithPosition:(uint32_t)marble_pos index:(uint32_t)index {
    uint32_t marble_x = (marble_pos >> 16) - 1;
    uint32_t marble_y = (marble_pos & 0xFFFF) - 1;
    
    // create a RXDynamicPicture object and queue it for rendering
    NSRect sampling_rect = NSMakeRect(0.f, index * 2, 4.f, 2.f);
    
    rx_core_rect_t core_display_rect;
    if (marble_pos == 0) {
        core_display_rect.left = tiny_marble_receptable_position_vectors[0][index];
        core_display_rect.top = tiny_marble_receptable_position_vectors[1][index];
    } else {
        // special exception rule: we draw nothing if the marble is in the last column
        if (marble_y == 24)
            return;
        
        NSPoint p1 = NSMakePoint(11834.f/39.f, 4321.f/39.f);
        NSPoint p2 = NSMakePoint(tiny_marble_offset_matrix[0][marble_x / 5] + 5 * (marble_x % 5),
                                 tiny_marble_offset_matrix[1][0]);
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

DEFINE_COMMAND(xt7600_setupmarbles) {
    // this command draws the "tiny marbles" bitmaps on tspit 227
    
    // load the tiny marble atlas if we haven't done so yet
    if (!tiny_marble_atlas) {
        NSString* tma_path = [[NSBundle mainBundle] pathForResource:@"tiny_marbles" ofType:@"png"];
        if (!tma_path)
            @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                           reason:@"Unable to find tiny_marbles.png."
                                         userInfo:nil];
        
        CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)[NSURL fileURLWithPath:tma_path], NULL);
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);
        
        size_t width = CGImageGetWidth(image);
        size_t height = CGImageGetHeight(image);
        CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(image));
        CFRelease(image);
        
        // get the load context and lock it
        CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
        CGLLockContext(cgl_ctx);
        
        // create, bind and configure the tiny marble texture atlas
        glGenTextures(1, &tiny_marble_atlas);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, tiny_marble_atlas); glReportError();
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST); glReportError();
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST); glReportError();
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE); glReportError();
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE); glReportError();
        
        // disable client storage for this texture unpack operation (we just keep the texture alive in GL for ever)
        glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_FALSE);
        
        // unpack the texture
        glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, 16, 16, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL); glReportError();
        glTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, 0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, CFDataGetBytePtr(data)); glReportError();
        glFlush();
        
        // re-enable client storage
        glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE); glReportError();
        
        CGLUnlockContext(cgl_ctx);
        CFRelease(data);
    }
    
    RXGameState* gs = [g_world gameState];
    [self _drawTinyMarbleWithPosition:[gs unsigned32ForKey:@"tred"] index:0];
    [self _drawTinyMarbleWithPosition:[gs unsigned32ForKey:@"torange"] index:1];
    [self _drawTinyMarbleWithPosition:[gs unsigned32ForKey:@"tyellow"] index:2];
    [self _drawTinyMarbleWithPosition:[gs unsigned32ForKey:@"tgreen"] index:3];
    [self _drawTinyMarbleWithPosition:[gs unsigned32ForKey:@"tblue"] index:4];
    [self _drawTinyMarbleWithPosition:[gs unsigned32ForKey:@"tviolet"] index:5];
}

- (void)_initializeMarbleHotspotWithVariable:(NSString*)marble_var initialRectPointer:(rx_core_rect_t*)initial_rect_ptr {
    RXGameState* gs = [g_world gameState];
    NSMapTable* hotspots_map = [card hotspotsNameMap];
    
    RXHotspot* hotspot = (RXHotspot*)NSMapGet(hotspots_map, marble_var);
    *initial_rect_ptr = [hotspot coreFrame];
    uint32_t marble_pos = [gs unsigned32ForKey:marble_var];
    if (marble_pos)  {
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

DEFINE_COMMAND(xt7800_setup) {
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

- (void)_drawMarbleWithVariable:(NSString*)marble_var marbleEnum:(rx_fire_marble_t)marble bitmapID:(uint16_t)bitmap_id activeMarble:(rx_fire_marble_t)active_marble {
    if (active_marble == marble)
        return;
    
    RXHotspot* hotspot = (RXHotspot*)NSMapGet([card hotspotsNameMap], marble_var);
    rx_core_rect_t hotspot_rect = [hotspot coreFrame];
    hotspot_rect.left += 3;
    hotspot_rect.top += 3;
    hotspot_rect.right += 3;
    hotspot_rect.bottom += 3;
    
    NSRect display_rect = RXMakeCompositeDisplayRectFromCoreRect(hotspot_rect);
    [self _drawPictureWithID:bitmap_id
                     archive:[g_world extraBitmapsArchive]
                 displayRect:display_rect
                samplingRect:NSMakeRect(0.0f, 0.0f, 0.0f, 0.0f)];
}

DEFINE_COMMAND(xdrawmarbles) {
    RXGameState* gs = [g_world gameState];
    rx_fire_marble_t active_marble = (rx_fire_marble_t)[gs unsigned32ForKey:@"themarble"];
    
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1);
    [self _drawMarbleWithVariable:@"tblue" marbleEnum:BLUE_MARBLE bitmapID:blue_marble_tBMP activeMarble:active_marble];
    [self _drawMarbleWithVariable:@"tgreen" marbleEnum:GREEN_MARBLE bitmapID:green_marble_tBMP activeMarble:active_marble];
    [self _drawMarbleWithVariable:@"torange" marbleEnum:ORANGE_MARBLE bitmapID:orange_marble_tBMP activeMarble:active_marble];
    [self _drawMarbleWithVariable:@"tviolet" marbleEnum:PURPLE_MARBLE bitmapID:violet_marble_tBMP activeMarble:active_marble];
    [self _drawMarbleWithVariable:@"tred" marbleEnum:RED_MARBLE bitmapID:red_marble_tBMP activeMarble:active_marble];
    [self _drawMarbleWithVariable:@"tyellow" marbleEnum:YELLOW_MARBLE bitmapID:yellow_marble_tBMP activeMarble:active_marble];
}

DEFINE_COMMAND(xtakeit) {
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
    while ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                    beforeDate:[NSDate dateWithTimeIntervalSinceNow:k_mouse_tracking_loop_period]] &&
           isfinite(mouse_vector.size.width))
    {
        mouse_vector = [controller mouseVector];
    }
    
    // update the marble's position
    rx_core_rect_t core_position = RXTransformRectWorldToCore(mouse_vector);
#if defined(DEBUG)
    RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@core position of mouse is <%u, %u>",
        logPrefix, core_position.left, core_position.top);
#endif
    
    NSRect grid_rect = NSMakeRect(marble_offset_matrix[0][0],
                                  marble_offset_matrix[1][0],
                                  marble_offset_matrix[0][4] + marble_size * 5 - marble_offset_matrix[0][0],
                                  marble_offset_matrix[1][4] + marble_size * 5 - marble_offset_matrix[1][0]);
    NSPoint core_rect_ns = NSMakePoint(core_position.left, core_position.top);
    
    // new marble position; UINT32_MAX indicates "invalid" and will cause the marble to reset to its initial position
    uint32_t marble_pos;
    uint32_t new_marble_pos = UINT32_MAX;
    uint32_t marble_x = UINT32_MAX;
    uint32_t marble_y = UINT32_MAX;
    
    if (NSPointInRect(core_rect_ns, grid_rect)) {
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
    RXHotspot* hotspot = (RXHotspot*)NSMapGet([card hotspotsNameMap], marble_var);
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

DEFINE_COMMAND(xt7500_checkmarbles) {
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

DEFINE_COMMAND(xgwt200_scribetime) {
    [[g_world gameState] setUnsigned64:(uint64_t)(CFAbsoluteTimeGetCurrent() * 1000) forKey:@"gScribeTime"];
}

DEFINE_COMMAND(xgwt900_scribe) {
    RXGameState* gs = [g_world gameState];
    uint64_t scribe_time = [gs unsigned64ForKey:@"gScribeTime"];
    uint32_t scribe = [gs unsigned32ForKey:@"gScribe"];
    if (scribe == 1 && (uint64_t)(CFAbsoluteTimeGetCurrent() * 1000) > scribe_time + 40000)
        [gs setUnsigned32:2 forKey:@"gScribe"];
}

#pragma mark -
#pragma mark gspit left viewer

static const uint16_t prison_activity_movies[3][8] = {
    {9, 10, 19, 19, 21, 21},
    {18, 20, 22},
    {11, 11, 12, 17, 17, 17, 17, 23}
};

- (void)_playRandomPrisonActivityMovie:(NSTimer*)timer {
    RXGameState* gs = [g_world gameState];
    uint32_t cath_state = [gs unsigned32ForKey:@"gCathState"];
    
    uint16_t prison_mlst;
    if (cath_state == 1)
        prison_mlst = prison_activity_movies[0][random() % 6];
    else if (cath_state == 2)
        prison_mlst = prison_activity_movies[1][random() % 3];
    else if (cath_state == 3)
        prison_mlst = prison_activity_movies[2][random() % 8];
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
    RXMovie* movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)(uintptr_t)30);
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_MLST_AND_START, prison_mlst);
    if (movie)
        [controller disableMovie:movie];
    
    // schedule the next prison activity movie
    NSTimeInterval delay;
    movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)(uintptr_t)30);
    QTGetTimeInterval([movie duration], &delay);
    delay += (random() % 30) + (random() % 30) + 2;
    
    [event_timer invalidate];
    event_timer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                           target:self
                                                         selector:@selector(_playRandomPrisonActivityMovie:)
                                                         userInfo:nil
                                                          repeats:NO];
}

DEFINE_COMMAND(xglview_prisonon) {
    RXGameState* gs = [g_world gameState];
    
    // set gLView to indicate the left viewer is on
    [gs setUnsigned32:1 forKey:@"gLView"];
    
    // MLST 8 to 23 (16 movies) are the prison activity movies; pick one
    uint16_t prison_mlst = random() % 16 + 8;
    
    // now need to select the correct viewer turn on movie and catherine state based on the selection above
    uintptr_t turnon_code;
    uint16_t cath_state;
    if (prison_mlst == 8 || prison_mlst == 10 || prison_mlst == 13 || prison_mlst >= 16 && prison_mlst <= 18 || prison_mlst == 20) {
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
    }
    
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
        NSMapRemove(code2movieMap, (const void*)(uintptr_t)30);
    
    // enable screen updates
    DISPATCH_COMMAND0(RX_COMMAND_ENABLE_SCREEN_UPDATES);
    
    // schedule the next prison activity movie
    uintptr_t k = 30;
    RXMovie* movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)k);
    NSTimeInterval delay;
    if (movie) {
        QTGetTimeInterval([movie duration], &delay);
        delay += (random() % 30) + (random() % 30) + 2;
    } else
        delay = 10.0 + (random() % 5) + (random() % 5) + 2;
    
    [event_timer invalidate];
    event_timer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                           target:self
                                                         selector:@selector(_playRandomPrisonActivityMovie:)
                                                         userInfo:nil
                                                          repeats:NO];
}

DEFINE_COMMAND(xglview_prisonoff) {
    // set gLView to indicate the viewer is off
    [[g_world gameState] setUnsigned32:0 forKey:@"gLView"];
    
    // invalidate the prison viewer timer
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

DEFINE_COMMAND(xglview_villageon) {
    RXGameState* gs = [g_world gameState];
    
    // set gLView to indicate the right viewer is on
    [gs setUnsigned32:2 forKey:@"gLView"];
    
    // activate the correct village viewer picture
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 2 + [gs unsignedShortForKey:@"gLViewPos"]);
}

DEFINE_COMMAND(xglview_villageoff) {
    // set gLView to indicate the viewer is off
    [[g_world gameState] setUnsigned32:0 forKey:@"gLView"];
    
    // activate the viewer off picture
    DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1);
}

static int64_t left_viewer_spin_timevals[] = {0LL, 816LL, 1617LL, 2416LL, 3216LL, 4016LL, 4816LL, 5616LL, 6416LL, 7216LL, 8016LL, 8816LL};

- (void)_configureLeftViewerSpinMovie {
    RXGameState* gs = [g_world gameState];
    NSString* hn = [_current_hotspot name];
    
    // determine the new left viewer position based on the hotspot name
    uint32_t old_pos = [gs unsigned32ForKey:@"gLViewPos"];
    uint32_t new_pos = old_pos + [[hn substringFromIndex:[hn length] - 1] intValue];
    
    // determine the playback selection for the viewer spin movie
    RXMovie* movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)(uintptr_t)1);
    QTTime duration = [movie duration];

    QTTime start_time = QTMakeTime(left_viewer_spin_timevals[old_pos], duration.timeScale);
    QTTimeRange movie_range = QTMakeTimeRange(start_time,
                                              QTMakeTime(left_viewer_spin_timevals[new_pos] - start_time.timeValue, duration.timeScale));
    [movie setPlaybackSelection:movie_range];
    
    // update the position variable
    [gs setUnsigned32:new_pos % 6 forKey:@"gLViewPos"];
}

DEFINE_COMMAND(xglviewer) {
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

static int64_t right_viewer_spin_timevals[] = {0LL, 816LL, 1617LL, 2416LL, 3216LL, 4016LL, 4816LL, 5616LL, 6416LL, 7216LL, 8016LL, 8816LL};

- (void)_configureRightViewerSpinMovie {
    RXGameState* gs = [g_world gameState];
    NSString* hn = [_current_hotspot name];
    
    // determine the new right viewer position based on the hotspot name
    uint32_t old_pos = [gs unsigned32ForKey:@"gRViewPos"];
    uint32_t new_pos = old_pos + [[hn substringFromIndex:[hn length] - 1] intValue];
    
    // determine the playback selection for the viewer spin movie
    RXMovie* movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)(uintptr_t)1);
    QTTime duration = [movie duration];

    QTTime start_time = QTMakeTime(right_viewer_spin_timevals[old_pos], duration.timeScale);
    QTTimeRange movie_range = QTMakeTimeRange(start_time,
                                              QTMakeTime(right_viewer_spin_timevals[new_pos] - start_time.timeValue,
                                                         duration.timeScale));
    [movie setPlaybackSelection:movie_range];
    
    // update the position variable
    [gs setUnsigned32:new_pos % 6 forKey:@"gRViewPos"];
}

DEFINE_COMMAND(xgrviewer) {
    RXGameState* gs = [g_world gameState];
    
    // if the viewer light is active, we need to turn it off first
    uint32_t viewer_light = [gs unsigned32ForKey:@"gRView"];
    if (viewer_light == 1) {
        [gs setUnsigned32:0 forKey:@"gRView"];
        
        uint16_t button_up_sound = [[card parent] dataSoundIDForName:[NSString stringWithFormat:@"%hu_gScpBtnUp_1",
                                                                      [[card descriptor] ID]]];
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

- (void)_playWharkSolo:(NSTimer*)timer {
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
    uint32_t whark_solo = (random() % 9) + 1;
    
    // play the solo
    uint16_t solo_sound = [[card parent] dataSoundIDForName:[NSString stringWithFormat:@"%hu_gWharkSolo%d_1",
                                                             whark_solo_card, whark_solo]];
    [self _playDataSoundWithID:solo_sound gain:1.0f duration:NULL];
    
    if (play_solo)
        // schedule the next one within the next 5 minutes but no sooner than in 2 minutes
        event_timer = [NSTimer scheduledTimerWithTimeInterval:120 + (random() % 180) + 1
                                                       target:self
                                                     selector:@selector(_playWharkSolo:)
                                                     userInfo:nil
                                                      repeats:NO];
    else {
        // we got here if played_whark_solo was NO (so we forced the solo to
        // play), but play_solo is NO, meaning we should not schedule another
        // solo; invalidate the event timer and set it to nil (setting it to
        // nil will allow xgwharksnd to re-schedule solos again)
        [event_timer invalidate];
        event_timer = nil;
    }

    // we have no played a solo
    played_one_whark_solo = YES;
}

DEFINE_COMMAND(xgwharksnd) {
    // cache the solo card ID (to be able to get a reference to the solo
    // sounds)
    whark_solo_card = [[card descriptor] ID];
    
    // play a solo within the next 5 seconds if we've never played one before
    // otherwise within the next 5 minutes but no sooner than in 2 minutes;
    // only do the above if the event timer is nil, otherwise don't disturb it
    // (e.g. if the player toggles the light rapidly, don't keep re-scheduling
    // the next solo)
    if (event_timer)
        return;
    
    if (!played_one_whark_solo)
        event_timer = [NSTimer scheduledTimerWithTimeInterval:(random() % 5) + 1
                                                       target:self
                                                     selector:@selector(_playWharkSolo:)
                                                     userInfo:nil
                                                      repeats:NO];
    else
        event_timer = [NSTimer scheduledTimerWithTimeInterval:120 + (random() % 180) + 1
                                                       target:self
                                                     selector:@selector(_playWharkSolo:)
                                                     userInfo:nil
                                                      repeats:NO];
}

DEFINE_COMMAND(xgplaywhark) {
    RXGameState* gs = [g_world gameState];
    
    uint32_t whark_visits = [gs unsigned32ForKey:@"gWhark"];
    uint64_t whark_state = [gs unsigned64ForKey:@"gWharkTime"];
    
    // if gWharkTime is not 1, we don't do anything
    if (whark_state != 1)
        return;
    
    // count the number of times the red light has been light / the whark has come
    whark_visits++;
    if (whark_visits > 5)
        whark_visits = 5;
    [gs setUnsigned32:whark_visits forKey:@"gWhark"];
    
    // determine which movie to play based on the visit count
    uint16_t mlst_index;
    if (whark_visits == 1)
        mlst_index = 3; // first whark movie, where we get a good look at it
    else if (whark_visits == 2)
        mlst_index = (random() % 2) + 4; // random 4 or 5
    else if (whark_visits == 3)
        mlst_index = (random() % 2) + 6; // random 6 or 7
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

DEFINE_COMMAND(xgplateau3160_dopools) {
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

DEFINE_COMMAND(xvga1300_carriage) {
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
    if (_did_hide_mouse) {
        [controller showMouseCursor];
        _did_hide_mouse = NO;
    }
    
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
    while ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                    beforeDate:[NSDate dateWithTimeIntervalSinceNow:k_mouse_tracking_loop_period]])
    {
        // have we passed the trapeze window?
        if (trapeze_window_end < CFAbsoluteTimeGetCurrent())
            break;
        
        // if the mouse has been pressed, update the mouse down event
        rx_event_t event = [controller lastMouseDownEvent];
        if (event.timestamp > mouse_down_event.timestamp) {
            mouse_down_event = event;
            
            // check where the mouse was pressed, and if it is inside the
            // trapeze region, set mouse_was_pressed to YES and exit the loop
            if (NSPointInRect(mouse_down_event.location, trapeze_rect)) {
                mouse_was_pressed = YES;
                break;
            }
        }
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
    if (!_did_hide_mouse) {
        [controller hideMouseCursor];
        _did_hide_mouse = YES;
    }
    
    // schedule a forward transition
    transition = [[RXTransition alloc] initWithCode:16 region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
    [controller queueTransition:transition];
    [transition release];
    
    // go to card RMAP 101709
    uint16_t card_id = [[[card descriptor] parent] cardIDFromRMAPCode:101709];
    DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, card_id);
    
    // schedule a transition with code 12 (from left, push new and old)
    transition = [[RXTransition alloc] initWithCode:12 region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
    [controller queueTransition:transition];
    [transition release];
    
    // go to card RMAP 101045
    card_id = [[[card descriptor] parent] cardIDFromRMAPCode:101045];
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
    card_id = [[[card descriptor] parent] cardIDFromRMAPCode:94567];
    DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, card_id);
}

#pragma mark -
#pragma mark gspit topology viewer

static int64_t pin_rotate_timevals[] = {8416LL, 0LL, 1216LL, 2416LL, 3616LL, 4816LL, 6016LL, 7216LL};

- (void)_configurePinMovieForRotation {
    RXGameState* gs = [g_world gameState];
    
    // get the old (current) position, the new position and the current pin movie code
    int32_t old_pos = [gs unsigned32ForKey:@"gPinPos"];
    int32_t new_pos = old_pos + 1;
    uintptr_t pin_movie_code = [gs unsigned32ForKey:@"gUpMoov"];
    
    // determine the playback selection for the pin movie
    RXMovie* movie = (RXMovie*)NSMapGet(code2movieMap, (const void*)pin_movie_code);
    QTTime duration = [movie duration];

    QTTime start_time = QTMakeTime(pin_rotate_timevals[old_pos], duration.timeScale);
    QTTimeRange movie_range = QTMakeTimeRange(start_time,
                                              QTMakeTime(pin_rotate_timevals[new_pos] - start_time.timeValue,
                                                         duration.timeScale));
    [movie setPlaybackSelection:movie_range];
    
    // update the position variable
    [gs setUnsigned32:(new_pos % 4) + 1 forKey:@"gPinPos"];
}

DEFINE_COMMAND(xgrotatepins) {
    RXGameState* gs = [g_world gameState];
    
    // if no pins are raised, we do nothing
    if (![gs unsigned32ForKey:@"gPinUp"])
        return;
    
    // configure the raised pin movie for a rotation
    [self performSelectorOnMainThread:@selector(_configurePinMovieForRotation) withObject:nil waitUntilDone:YES];
    
    // get the raised pin movie
    uintptr_t pin_movie_code = [gs unsigned32ForKey:@"gUpMoov"];
    
    // get the pin rotation sound
    uint16_t pin_rotation_sound = [[card parent] dataSoundIDForName:[NSString stringWithFormat:@"%hu_gPinsRot_1",
                                                                     [[card descriptor] ID]]];
    
    // play the pin rotate sound and movie
    [self _playDataSoundWithID:pin_rotation_sound gain:1.0f duration:NULL];
    DISPATCH_COMMAND1(RX_COMMAND_START_MOVIE_BLOCKING, pin_movie_code);
}

DEFINE_COMMAND(xgpincontrols) {

}

DEFINE_COMMAND(xglowerpins) {

}

DEFINE_COMMAND(xgraisepins) {

}

DEFINE_COMMAND(xgresetpins) {
    uint16_t pin_up = [[g_world gameState] unsignedShortForKey:@"gPinUp"];
    rx_dispatch_external1(self, @"xglowerpins", pin_up);
}

@end
