//
//  RXScriptEngine.m
//  rivenx
//
//  Created by Jean-Francois Roy on 31/01/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import "RXScriptEngine.h"

typedef void (*rx_command_imp_t)(id, SEL, const uint16_t, const uint16_t*);
struct _rx_command_dispatch_entry {
	rx_command_imp_t imp;
	SEL sel;
};
typedef struct _rx_command_dispatch_entry rx_command_dispatch_entry_t;

CF_INLINE void rx_dispatch_commandv(id target, rx_command_dispatch_entry_t* command, uint16_t argc, uint16_t* argv) {
	command->imp(target, command->sel, argc, argv);
}

CF_INLINE void rx_dispatch_command0(id target, rx_command_dispatch_entry_t* command) {
	rx_dispatch_commandv(target, command, 0, NULL);
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

static rx_command_dispatch_entry_t _riven_command_dispatch_table[47];
static NSMapTable* _riven_external_command_dispatch_map;


@implementation RXScriptEngine

+ (void)initialize {
	static BOOL initialized = NO;
	if (initialized)
		return;
	initialized = YES;
	
	// build the principal command dispatch table
	_riven_command_dispatch_table[0].sel = @selector(_invalid_opcode:arguments:);
	_riven_command_dispatch_table[1].sel = @selector(_opcode_drawDynamicPicture:arguments:);
	_riven_command_dispatch_table[2].sel = @selector(_opcode_goToCard:arguments:);
	_riven_command_dispatch_table[3].sel = @selector(_opcode_enableSynthesizedSLST:arguments:);
	_riven_command_dispatch_table[4].sel = @selector(_opcode_playLocalSound:arguments:);
	_riven_command_dispatch_table[5].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[6].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[7].sel = @selector(_opcode_setVariable:arguments:);
	_riven_command_dispatch_table[8].sel = @selector(_invalid_opcode:arguments:);
	_riven_command_dispatch_table[9].sel = @selector(_opcode_enableHotspot:arguments:);
	_riven_command_dispatch_table[10].sel = @selector(_opcode_disableHotspot:arguments:);
	_riven_command_dispatch_table[11].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[12].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[13].sel = @selector(_opcode_setCursor:arguments:);
	_riven_command_dispatch_table[14].sel = @selector(_opcode_pause:arguments:);
	_riven_command_dispatch_table[15].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[16].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[17].sel = @selector(_opcode_callExternal:arguments:);
	_riven_command_dispatch_table[18].sel = @selector(_opcode_scheduleTransition:arguments:);
	_riven_command_dispatch_table[19].sel = @selector(_opcode_reloadCard:arguments:);
	_riven_command_dispatch_table[20].sel = @selector(_opcode_disableAutomaticSwaps:arguments:);
	_riven_command_dispatch_table[21].sel = @selector(_opcode_enableAutomaticSwaps:arguments:);
	_riven_command_dispatch_table[22].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[23].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[24].sel = @selector(_opcode_incrementVariable:arguments:);
	_riven_command_dispatch_table[25].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[26].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[27].sel = @selector(_opcode_goToStack:arguments:);
	_riven_command_dispatch_table[28].sel = @selector(_opcode_disableMovie:arguments:);
	_riven_command_dispatch_table[29].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[30].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[31].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[32].sel = @selector(_opcode_startMovieAndWaitUntilDone:arguments:);
	_riven_command_dispatch_table[33].sel = @selector(_opcode_startMovie:arguments:);
	_riven_command_dispatch_table[34].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[35].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[36].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[37].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[38].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[39].sel = @selector(_opcode_activatePLST:arguments:);
	_riven_command_dispatch_table[40].sel = @selector(_opcode_activateSLST:arguments:);
	_riven_command_dispatch_table[41].sel = @selector(_opcode_prepareMLST:arguments:);
	_riven_command_dispatch_table[42].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[43].sel = @selector(_opcode_activateBLST:arguments:);
	_riven_command_dispatch_table[44].sel = @selector(_opcode_activateFLST:arguments:);
	_riven_command_dispatch_table[45].sel = @selector(_opcode_noop:arguments:);
	_riven_command_dispatch_table[46].sel = @selector(_opcode_activateMLST:arguments:);
	
	for (unsigned char selectorIndex = 0; selectorIndex < 47; selectorIndex++)
		_riven_command_dispatch_table[selectorIndex].imp = (rx_command_imp_t)[self instanceMethodForSelector:_riven_command_dispatch_table[selectorIndex].sel];
	
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
				NSString* external_name = [method_selector_string substringWithRange:NSMakeRange([(NSString*)@"_external_" length], first_colon_range.location - [(NSString*)@"_external_" length])];
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

- (void)initWithController:(id<RXScriptEngineControllerProtocol>)ctlr {
	self = [super init];
	if (!self)
		return nil;
	
	controller = ctlr;
	
	logPrefix = [NSMutableString new];
	code2movieMap = NSCreateMapTable(NSIntMapKeyCallBacks, NSObjectMapValueCallBacks, 0);
	
	return self;
}

- (void)dealloc {
	[logPrefix release];
	NSFreeMapTable(code2movieMap);
	
	[super dealloc];
}

#pragma mark -
#pragma mark script execution

- (size_t)_executeRivenProgram:(const void *)program count:(uint16_t)opcodeCount {
	if (!controller)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"NO RIVEN SCRIPT HANDLER" userInfo:nil];
	
	RXStack* parent = [_descriptor parent];
	
	// bump the execution depth
	_programExecutionDepth++;
	
	size_t programOffset = 0;
	const uint16_t* shortedProgram = (uint16_t *)program;
	
	uint16_t pc = 0;
	for (; pc < opcodeCount; pc++) {
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
				[self _executeRivenProgram:((uint16_t*)BUFFER_OFFSET(program, defaultCaseOffset)) + 2 count:*(((uint16_t*)BUFFER_OFFSET(program, defaultCaseOffset)) + 1)];
				
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
			_riven_command_dispatch_table[*shortedProgram].imp(self, _riven_command_dispatch_table[*shortedProgram].sel, *(shortedProgram + 1), shortedProgram + 2);
			_lastExecutedProgramOpcode = *shortedProgram;
			
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
	
	return programOffset;
}

- (void)_runScreenUpdatePrograms {
#if defined(DEBUG)
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@screen update {", logPrefix);
	[logPrefix appendString:@"    "];
#endif
	
	// this is a bit of a hack, but disable automatic render state swaps while running screen update programs
	_renderStateSwapsEnabled = NO;
	
	NSArray* programs = [_cardEvents objectForKey:k_eventSelectors[10]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
	// re-enable render state swaps (they must be enabled if we just ran screen update programs)
	_renderStateSwapsEnabled = YES;
	
#if defined(DEBUG)
	[logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
}

- (void)_swapRenderState {
	// WARNING: THIS IS NOT THREAD SAFE, BUT WILL NOT INTERFERE WITH THE RENDER THREAD NEGATIVELY
	
	// if swaps are disabled, return immediatly
	if (!_renderStateSwapsEnabled) {
#if defined(DEBUG)
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"render state swap request ignored because swapping is disabled");
#endif
		return;
	}	
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"swapping render state");
#endif

	// run screen update programs
	[self _runScreenUpdatePrograms];
	
	// the script handler will set our front render state to our back render state at the appropriate moment; when this returns, the swap has occured (front == back)
	[controller update];
}

#pragma mark -

- (void)prepareForRendering {
#if defined(DEBUG)
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@preparing for rendering {", logPrefix);
	[logPrefix appendString:@"    "];
#endif

	// retain the card while it executes programs
	if (_programExecutionDepth == 0) {
		[self retain];
	}

	// disable automatic render state swaps by faking an execution of opcode 20
	_riven_command_dispatch_table[20].imp(self, _riven_command_dispatch_table[20].sel, 0, NULL);
	 
	// stop all playing movies (this will probably only ever include looping movies or non-blocking movies)
//	[(NSObject*)controller performSelectorOnMainThread:@selector(disableAllMovies) withObject:nil waitUntilDone:YES];
//	NSResetMapTable(code2movieMap);
	
	OSSpinLockLock(&_activeHotspotsLock);
	[_activeHotspots removeAllObjects];
	[_activeHotspots addObjectsFromArray:_hotspots];
	[_activeHotspots makeObjectsPerformSelector:@selector(enable)];
	[_activeHotspots sortUsingSelector:@selector(compareByID:)];
	OSSpinLockUnlock(&_activeHotspotsLock);
	
	// reset auto-activation states
	_didActivatePLST = NO;
	_didActivateSLST = NO;
	
	// reset the transition queue flag
	_queuedAPushTransition = NO;
	
	// reset water animation
	[controller queueSpecialEffect:NULL owner:self];
	
	// execute loading programs (index 6)
	NSArray* programs = [_cardEvents objectForKey:k_eventSelectors[6]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for(; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
	// activate the first picture if none has been enabled already
	if (_pictureCount > 0 && !_didActivatePLST) {
#if defined(DEBUG)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@automatically activating first plst record", logPrefix);
#endif
		DISPATCH_COMMAND1(RX_COMMAND_ACTIVATE_PLST, 1);
	}
	
	// swap render state (by faking an execution of command 21 -- _opcode_enableAutomaticSwaps)
	 _riven_command_dispatch_table[21].imp(self, _riven_command_dispatch_table[21].sel, 0, NULL);
	 
#if defined(DEBUG)
	[logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
	
	// release the card if it no longer is executing programs
	if (_programExecutionDepth == 0) {
		[self release];
		
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
	if (_programExecutionDepth == 0) {
		[self retain];
	}
	
	// execute rendering programs (index 9)
	NSArray* programs = [_cardEvents objectForKey:k_eventSelectors[9]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
	// activate the first sound group if none has been enabled already
	if ([_soundGroups count] > 0 && !_didActivateSLST) {
#if defined(DEBUG)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@automatically activating first slst record", logPrefix);
#endif
		[controller activateSoundGroup:[_soundGroups objectAtIndex:0]];
	}
	_didActivateSLST = YES;
	
#if defined(DEBUG)
	[logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

	// release the card if it no longer is executing programs
	if (_programExecutionDepth == 0) {
		[self release];
		
		// if the card hid the mouse cursor while executing programs, we can now show it again
		if (_did_hide_mouse) {
			[controller showMouseCursor];
			_did_hide_mouse = NO;
		}
	}
}

- (void)stopRendering {
#if defined(DEBUG)
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@stopping rendering {", logPrefix);
	[logPrefix appendString:@"    "];
#endif

	// retain the card while it executes programs
	if (_programExecutionDepth == 0) {
		[self retain];
	}
	
	// execute leaving programs (index 7)
	NSArray* programs = [_cardEvents objectForKey:k_eventSelectors[7]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
#if defined(DEBUG)
	[logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

	// release the card if it no longer is executing programs
	if (_programExecutionDepth == 0) {
		[self release];
		
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
	if (_programExecutionDepth == 0) {
		[self retain];
	}
	
	// execute mouse moved programs (index 4)
	NSArray* programs = [[hotspot script] objectForKey:k_eventSelectors[4]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
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
		[self release];
		
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
	if (_programExecutionDepth == 0) {
		[self retain];
	}
	
	// execute mouse leave programs (index 5)
	NSArray* programs = [[hotspot script] objectForKey:k_eventSelectors[5]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
#if defined(DEBUG)
	[logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

	// release the card if it no longer is executing programs
	if (_programExecutionDepth == 0) {
		[self release];
		
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
	if (_programExecutionDepth == 0) {
		[self retain];
	}
	
	// execute mouse down programs (index 0)
	NSArray* programs = [[hotspot script] objectForKey:k_eventSelectors[0]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
#if defined(DEBUG)
	[logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

	// release the card if it no longer is executing programs
	if (_programExecutionDepth == 0) {
		[self release];
		
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
	if (_programExecutionDepth == 0) {
		[self retain];
	}
	
	// execute mouse up programs (index 2)
	NSArray* programs = [[hotspot script] objectForKey:k_eventSelectors[2]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
#if defined(DEBUG)
	[logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif

	// release the card if it no longer is executing programs
	if (_programExecutionDepth == 0) {
		[self release];
		
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

- (void)_handleMovieRateChange:(NSNotification*)notification {
	// WARNING: MUST RUN ON MAIN THREAD
	float rate = [[[notification userInfo] objectForKey:QTMovieRateDidChangeNotificationParameter] floatValue];
	if (rate < 0.001f) {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:QTMovieRateDidChangeNotification object:[notification object]];
	}
}

- (void)_handleBlockingMovieRateChange:(NSNotification*)notification {
	// WARNING: MUST RUN ON MAIN THREAD
	float rate = [[[notification userInfo] objectForKey:QTMovieRateDidChangeNotificationParameter] floatValue];
	if (rate < 0.001f) {
		[self _handleMovieRateChange:notification];
		
		// signal the movie playback semaphore to unblock the script thread
		semaphore_signal(_moviePlaybackSemaphore);
	}
}

- (void)_reallyDoPlayMovie:(RXMovie*)movie {
	// WARNING: MUST RUN ON MAIN THREAD
	
	// do nothing if the movie is already playing
	if ([[movie movie] rate] > 0.001f)
		return;
	
	// put the movie at its beginning if it is not a looping movie
	if (![movie looping])
		[movie gotoBeginning];
	
	// queue the movie for rendering
	[controller enableMovie:movie];
	
	// begin playback
	[[movie movie] play];
}

- (void)_playMovie:(RXMovie*)movie {
	// WARNING: MUST RUN ON MAIN THREAD
	
	// register for rate notifications on the non-blocking movie handler
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleMovieRateChange:) name:QTMovieRateDidChangeNotification object:[movie movie]];
	
	// play
	[self _reallyDoPlayMovie:movie];
}

- (void)_playBlockingMovie:(RXMovie*)movie {
	// WARNING: MUST RUN ON MAIN THREAD
	
	// register for rate notifications on the blocking movie handler
	[[NSNotificationCenter defaultCenter] removeObserver:self name:QTMovieRateDidChangeNotification object:[movie movie]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleBlockingMovieRateChange:) name:QTMovieRateDidChangeNotification object:[movie movie]];
	
	// hide the mouse cursor
	if (!_did_hide_mouse) {
		_did_hide_mouse = YES;
		[controller hideMouseCursor];
	}
	
	// start playing the movie (this may be a no-op if the movie was already started)
	[self _reallyDoPlayMovie:movie];
}

- (void)_stopMovie:(RXMovie*)movie {
	// disable the movie in the card renderer
	[controller disableMovie:movie];
	
	// stop playback
	[[movie movie] stop];
}

#pragma mark -
#pragma mark dynamic pictures

- (void)_drawPictureWithID:(uint16_t)ID archive:(MHKArchive*)archive displayRect:(NSRect)displayRect samplingRect:(NSRect)samplingRect {
	// get the resource descriptor for the tBMP resource
	NSError* error;
	NSDictionary* pictureDescriptor = [archive bitmapDescriptorWithID:ID error:&error];
	if (!pictureDescriptor)
		@throw [NSException exceptionWithName:@"RXPictureLoadException" reason:@"Could not get a picture resource's picture descriptor." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	// if the samplingRect is empty, use the picture's full resolution
	if (NSIsEmptyRect(samplingRect))
		samplingRect.size = NSMakeSize([[pictureDescriptor objectForKey:@"Width"] floatValue], [[pictureDescriptor objectForKey:@"Height"] floatValue]);
	if (displayRect.size.width > samplingRect.size.width)
		displayRect.size.width = samplingRect.size.width;
	if (displayRect.size.height > samplingRect.size.height)
		displayRect.size.height = samplingRect.size.height;
	
	// compute the size of the buffer needed to store the texture; we'll be using MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED as the texture format, which is 4 bytes per pixel
	GLsizeiptr pictureSize = [[pictureDescriptor objectForKey:@"Width"] intValue] * [[pictureDescriptor objectForKey:@"Height"] intValue] * 4;
	
	// check if we have a cache for the tBMP ID; create a dynamic picture structure otherwise and map it to the tBMP ID
	uintptr_t dynamicPictureKey = ID;
	struct rx_card_dynamic_picture* dynamicPicture = (struct rx_card_dynamic_picture*)NSMapGet(_dynamicPictureMap, (const void*)dynamicPictureKey);
	if (dynamicPicture == NULL) {
		dynamicPicture = reinterpret_cast<struct rx_card_dynamic_picture*>(malloc(sizeof(struct rx_card_dynamic_picture*)));
		
		// get the load context
		CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
		CGLLockContext(cgl_ctx);
		
		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, [RXDynamicPicture sharedDynamicPictureUnpackBuffer]); glReportError();
		GLvoid* pictureBuffer = glMapBuffer(GL_PIXEL_UNPACK_BUFFER, GL_WRITE_ONLY); glReportError();
		
		// load the picture in the mapped picture buffer
		if (![archive loadBitmapWithID:ID buffer:pictureBuffer format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED error:&error])
			@throw [NSException exceptionWithName:@"RXPictureLoadException" reason:@"Could not load a picture resource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
		
		// unmap the unpack buffer
		if (GLEE_APPLE_flush_buffer_range)
			glFlushMappedBufferRangeAPPLE(GL_PIXEL_UNPACK_BUFFER, 0, pictureSize);
		glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER); glReportError();
		
		// create a texture object and bind it
		glGenTextures(1, &dynamicPicture->texture); glReportError();
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, dynamicPicture->texture); glReportError();
		
		// texture parameters
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glReportError();
		
		// client storage is not compatible with PBO texture unpack
		glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_FALSE);
		
		// unpack the texture
		glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, [[pictureDescriptor objectForKey:@"Width"] intValue], [[pictureDescriptor objectForKey:@"Height"] intValue], 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, BUFFER_OFFSET(NULL, 0)); glReportError();
		
		// reset the unpack buffer state and re-enable client storage
		glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE); glReportError();
		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0); glReportError();
		
		// we created a new texture object, so flush
		glFlush();
		
		// unlock the load context
		CGLUnlockContext(cgl_ctx);
		
		// map the tBMP ID to the dynamic picture
		NSMapInsert(_dynamicPictureMap, (void*)dynamicPictureKey, dynamicPicture);
	}
	
	// create a RXDynamicPicture object and queue it for rendering
	RXDynamicPicture* picture = [[RXDynamicPicture alloc] initWithTexture:dynamicPicture->texture samplingRect:samplingRect renderRect:displayRect owner:self];
	[controller queuePicture:picture];
	[picture release];
	
	// swap the render state; this always marks the back render state as modified
	[self _swapRenderState];
}

#pragma mark -

- (void)_invalid_opcode:(const uint16_t)argc arguments:(const uint16_t *)argv {
	@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"INVALID RIVEN SCRIPT OPCODE EXECUTED: %d", argv[-2]] userInfo:nil];
}

- (void)_opcode_noop:(const uint16_t)argc arguments:(const uint16_t *)argv {
	uint16_t argi = 0;
	NSString* formatString;
	if (argv)
		formatString = [NSString stringWithFormat:@"WARNING: opcode %hu not implemented. arguments: {", *(argv - 2)];
	else
		formatString = [NSString stringWithFormat:@"WARNING: unknown opcode called (most likely the _opcode_enableAutomaticSwaps hack) {"];
	
	if (argc > 1) {
		for (; argi < argc - 1; argi++)
			formatString = [formatString stringByAppendingFormat:@"%hu, ", argv[argi]];
	}
	
	if (argc > 0)
		formatString = [formatString stringByAppendingFormat:@"%hu", argv[argi]];
	
	formatString = [formatString stringByAppendingString:@"}"];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@%@", logPrefix, formatString);
}

// 1
- (void)_opcode_drawDynamicPicture:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 9)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
	
	NSRect field_display_rect = RXMakeNSRect(argv[1], argv[2], argv[3], argv[4] - 1);
	NSRect sampling_rect = NSMakeRect(argv[5], argv[6], argv[7] - argv[5], argv[8] - argv[6]);
	
#if defined(DEBUG)
	if (!_disableScriptLogging)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@drawing dynamic picture ID %hu in rect {{%f, %f}, {%f, %f}}", logPrefix, argv[0], field_display_rect.origin.x, field_display_rect.origin.y, field_display_rect.size.width, field_display_rect.size.height);
#endif
	
	[self _drawPictureWithID:argv[0] archive:_archive displayRect:field_display_rect samplingRect:sampling_rect];
}

// 2
- (void)_opcode_goToCard:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
	if (!_disableScriptLogging)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@going to card ID %hu", logPrefix, argv[0]);
#endif

	RXStack* parent = [_descriptor parent];
	[controller setActiveCardWithStack:[parent key] ID:argv[0] waitUntilDone:YES];
}

// 3
- (void)_opcode_enableSynthesizedSLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
	if (!_disableScriptLogging)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling a synthesized slst record", logPrefix);
#endif

	RXSoundGroup* oldSoundGroup = _synthesizedSoundGroup;

	// argv + 1 is suitable for _createSoundGroupWithSLSTRecord
	uint16_t soundCount = argv[0];
	_synthesizedSoundGroup = [self _createSoundGroupWithSLSTRecord:(argv + 1) soundCount:soundCount swapBytes:NO];
	
	[controller activateSoundGroup:_synthesizedSoundGroup];
	[oldSoundGroup release];
}

// 4
- (void)_opcode_playLocalSound:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 3)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@playing local sound resource with id %hu, volume %hu", logPrefix, argv[0], argv[1]);
#endif
	
	RXDataSound* sound = [RXDataSound new];
	sound->parent = [_descriptor parent];
	sound->ID = argv[0];
	sound->gain = (float)argv[1] / kSoundGainDivisor;
	sound->pan = 0.5f;
	
	[controller playDataSound:sound];
	
	// EXPERIMENTAL: use argv[2] as a boolean to indicate "blocking" playback
	if (argv[2]) {
		double duration;
		if (sound->source)
			duration = sound->source->Duration();
		else {
			id <MHKAudioDecompression> decompressor = [sound audioDecompressor];
			duration = [decompressor frameCount] / [decompressor outputFormat].mSampleRate;
		}
		
		// hide the mouse cursor
		if (!_did_hide_mouse) {
			_did_hide_mouse = YES;
			[controller hideMouseCursor];
		}
		
		usleep(duration * 1E6);
	}
	
	[sound release];
}

// 7
- (void)_opcode_setVariable:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 2)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
	
	RXStack* parent = [_descriptor parent];
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
	
	uint32_t key = argv[0];
	RXHotspot* hotspot = reinterpret_cast<RXHotspot*>(NSMapGet(_hotspotsIDMap, (void*)key));
	assert(hotspot);
	
	if (!hotspot->enabled) {
		hotspot->enabled = YES;
		
		OSSpinLockLock(&_activeHotspotsLock);
		[_activeHotspots addObject:hotspot];
		[_activeHotspots sortUsingSelector:@selector(compareByID:)];
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
	
	uint32_t key = argv[0];
	RXHotspot* hotspot = reinterpret_cast<RXHotspot*>(NSMapGet(_hotspotsIDMap, (void *)key));
	assert(hotspot);
	
	if (hotspot->enabled) {
		hotspot->enabled = NO;
		
		OSSpinLockLock(&_activeHotspotsLock);
		[_activeHotspots removeObject:hotspot];
		[_activeHotspots sortUsingSelector:@selector(compareByID:)];
		OSSpinLockUnlock(&_activeHotspotsLock);
		
		// instruct the script handler to update the hotspot state
		[controller updateHotspotState];
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
	
	// hide the mouse cursor
	if (!_did_hide_mouse) {
		_did_hide_mouse = YES;
		[controller hideMouseCursor];
	}
	
	usleep(argv[0] * 1000);
}

// 17
- (void)_opcode_callExternal:(const uint16_t)argc arguments:(const uint16_t*)argv {
	uint16_t argi = 0;
	uint16_t externalID = argv[0];
	uint16_t extarnalArgc = argv[1];
	
	NSString* externalName = [[_descriptor parent] externalNameAtIndex:externalID];
	if (!externalName)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID EXTERNAL COMMAND ID" userInfo:nil];
	
#if defined(DEBUG)
	NSString* formatString = [NSString stringWithFormat:@"calling external %@(", externalName];
	
	if (extarnalArgc > 1) {
		for (; argi < extarnalArgc - 1; argi++)
			formatString = [formatString stringByAppendingFormat:@"%hu, ", argv[2 + argi]];
	}
	
	if (extarnalArgc > 0)
		formatString = [formatString stringByAppendingFormat:@"%hu", argv[2 + argi]];
	
	formatString = [formatString stringByAppendingString:@") {"];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@%@", logPrefix, formatString);
	
	// augment script log indentation for the external command
	[logPrefix appendString:@"    "];
#endif
	
	// dispatch the call to the external command
	rx_command_dispatch_entry_t* command_dispatch = (rx_command_dispatch_entry_t*)NSMapGet(_riven_external_command_dispatch_map, externalName);
	if (!command_dispatch) {
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@    WARNING: external command is not implemented!", logPrefix);
#if defined(DEBUG)
		[logPrefix deleteCharactersInRange:NSMakeRange([logPrefix length] - 4, 4)];
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", logPrefix);
#endif
		return;
	}
		
	command_dispatch->imp(self, command_dispatch->sel, extarnalArgc, argv + 2);
	
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
		rect = RXMakeNSRect(argv[1], argv[2], argv[3], argv[4]);
	else
		rect = NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height);
	
	RXTransition* transition = [[RXTransition alloc] initWithCode:code region:rect];

#if defined(DEBUG)
	if (!_disableScriptLogging)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelMessage, @"%@scheduling transition %@", logPrefix, transition);
#endif
	
	// queue the transition
	if (transition->type == RXTransitionDissolve && _lastExecutedProgramOpcode == 18 && _queuedAPushTransition)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelMessage, @"WARNING: dropping dissolve transition because last command queued a push transition");
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
	[controller setActiveCardWithStack:current_card->parentName ID:current_card->cardID waitUntilDone:YES];
}

// 20
- (void)_opcode_disableAutomaticSwaps:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
	if (argv != NULL)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling render state swaps", logPrefix);
	else
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling render state swaps before prepareForRendering execution", logPrefix);
#endif
	_renderStateSwapsEnabled = NO;
}

// 21
- (void)_opcode_enableAutomaticSwaps:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
	if (!_disableScriptLogging) {
		if (argv != NULL)
			RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling render state swaps", logPrefix);
		else
			RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling render state swaps after prepareForRendering execution", logPrefix);
	}
#endif
	
	// swap
	_renderStateSwapsEnabled = YES;
	[self _swapRenderState];
}

// 24
- (void)_opcode_incrementVariable:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 2)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
	
	RXStack* parent = [_descriptor parent];
	NSString* name = [parent varNameAtIndex:argv[0]];
	if (!name) name = [NSString stringWithFormat:@"%@%hu", [parent key], argv[0]];
#if defined(DEBUG)
	if (!_disableScriptLogging)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@incrementing variable %@ by %hu", logPrefix, name, argv[1]);
#endif
	
	uint16_t v = [[g_world gameState] unsignedShortForKey:name];
	[[g_world gameState] setUnsignedShort:(v + argv[1]) forKey:name];
}

// 27
- (void)_opcode_goToStack:(const uint16_t)argc arguments:(const uint16_t*) argv {
	if (argc < 3)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
	
	NSString* stackKey = [[_descriptor parent] stackNameAtIndex:argv[0]];
	// FIXME: we need to be smarter about stack management. For now, we try to load the stack once. And it stays loaded. Forver
	// make sure the requested stack has been loaded
	RXStack* stack = [g_world activeStackWithKey:stackKey];
	if (!stack)
		[g_world loadStackWithKey:stackKey waitUntilDone:YES];
	stack = [g_world activeStackWithKey:stackKey];
	
	uint32_t card_rmap = (argv[1] << 16) | argv[2];
	uint16_t card_id = [stack cardIDFromRMAPCode:card_rmap];
	
#if defined(DEBUG)
	if (!_disableScriptLogging)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@going to stack %@ on card ID %hu", logPrefix, stackKey, card_id);
#endif
	
	[controller setActiveCardWithStack:stackKey ID:card_id waitUntilDone:YES];
}

// 28
- (void)_opcode_disableMovie:(const uint16_t)argc arguments:(const uint16_t*) argv {
	if (argc < 1)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
	
#if defined(DEBUG)
	if (!_disableScriptLogging)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling movie with code %hu", logPrefix, argv[0]);
#endif
	
	// get the movie object
	uintptr_t k = argv[0];
	RXMovie* movie = reinterpret_cast<RXMovie*>(NSMapGet(code2movieMap, (const void*)k));
	assert(movie);
	
	// stop the movie on the main thread and block until done
	[self performSelectorOnMainThread:@selector(_stopMovie:) withObject:movie waitUntilDone:YES];
	
	// remove the movie from the code-movie map
	NSMapRemove(code2movieMap, (const void*)k);
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
	RXMovie* movie = reinterpret_cast<RXMovie*>(NSMapGet(code2movieMap, (const void*)k));
	assert(movie);
	
	// start the movie and register for rate change notifications
	[self performSelectorOnMainThread:@selector(_playBlockingMovie:) withObject:movie waitUntilDone:YES];
	
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
	RXMovie* movie = reinterpret_cast<RXMovie*>(NSMapGet(code2movieMap, (const void*)k));
	assert(movie);
	
	// start the movie
	[self performSelectorOnMainThread:@selector(_playMovie:) withObject:movie waitUntilDone:YES];
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
	RXPicture* picture = [[RXPicture alloc] initWithTexture:_pictureTextures[index] vao:_pictureVAO index:4 * index owner:self];
	[controller queuePicture:picture];
	[picture release];
	
	// opcode 39 triggers a render state swap
	[self _swapRenderState];
	
	// indicate that an PLST record has been activated (to manage the automatic activation of PLST record 1 if none has been)
	_didActivatePLST = YES;
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
	[controller activateSoundGroup:[_soundGroups objectAtIndex:argv[0] - 1]];
	
	// indicate that an SLST record has been activated (to manage the automatic activation of SLST record 1 if none has been)
	_didActivateSLST = YES;
}

// 41
- (void)_opcode_prepareMLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 1)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
	uintptr_t k = _mlstCodes[argv[0] - 1];
	
#if defined(DEBUG)
	if (!_disableScriptLogging)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelMessage, @"%@activating and playing in background mlst record %hu, code %hu (u0=%hu)", logPrefix, argv[0], k, argv[1]);
#endif
	
	// update the code to movie map
	RXMovie* movie = [_movies objectAtIndex:argv[0] - 1];
	NSMapInsert(code2movieMap, (const void*)k, movie);
	
	// start the movie
	[self performSelectorOnMainThread:@selector(_playMovie:) withObject:movie waitUntilDone:YES];
}

// 43
- (void)_opcode_activateBLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 1)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating blst record at index %hu", logPrefix, argv[0]);
#endif
	
	struct rx_blst_record* record = (struct rx_blst_record*)_hotspotControlRecords + (argv[0] - 1);
	uint32_t key = record->hotspot_id;
	
	RXHotspot* hotspot = reinterpret_cast<RXHotspot*>(NSMapGet(_hotspotsIDMap, (void *)key));
	assert(hotspot);
	
	OSSpinLockLock(&_activeHotspotsLock);
	if (record->enabled == 1 && !hotspot->enabled)
		[_activeHotspots addObject:hotspot];
	else if (record->enabled == 0 && hotspot->enabled)
		[_activeHotspots removeObject:hotspot];
	OSSpinLockUnlock(&_activeHotspotsLock);
	
	hotspot->enabled = record->enabled;
	
	OSSpinLockLock(&_activeHotspotsLock);
	[_activeHotspots sortUsingSelector:@selector(compareByID:)];
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

	[controller queueSpecialEffect:_sfxes + (argv[0] - 1) owner:self];
}

// 46
- (void)_opcode_activateMLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 2)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
	uintptr_t k = _mlstCodes[argv[0] - 1];

#if defined(DEBUG)
	if (!_disableScriptLogging)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating mlst record %hu, code %hu (u0=%hu)", logPrefix, argv[0], k, argv[1]);
#endif
	
	// update the code to movie map
	RXMovie* movie = [_movies objectAtIndex:argv[0] - 1];
	NSMapInsert(code2movieMap, (const void*)k, movie);
}

@end


#pragma mark -
@implementation RXCard (RXCardExternals)

#define DEFINE_COMMAND(NAME) - (void)_external_ ## NAME:(const uint16_t)argc arguments:(const uint16_t*)argv

#pragma mark -
#pragma mark setup

DEFINE_COMMAND(xasetupcomplete) {
	// schedule a fade transition
	DISPATCH_COMMAND1(18, 16);
	
	// activate an empty sound group with fade out to clear any playing sound from the sound setup card
	RXSoundGroup* sgroup = [RXSoundGroup new];
	sgroup->gain = 1.0f;
	sgroup->loop = NO;
	sgroup->fadeOutActiveGroupBeforeActivating = YES;
	sgroup->fadeInOnActivation = NO;
	[controller activateSoundGroup:sgroup];
	[sgroup release];
	
	// go to card 1
	DISPATCH_COMMAND1(2, 1);
}

#pragma mark -
#pragma mark shared journal support

- (void)_returnFromJournal {
	// schedule a cross-fade transition to the return card
	RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionDissolve direction:0 region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
	[controller queueTransition:transition];
	[transition release];
	
	// change the active card to the saved return card
	RXSimpleCardDescriptor* returnCard = [[g_world gameState] returnCard];
	[controller setActiveCardWithStack:returnCard->parentName ID:returnCard->cardID waitUntilDone:YES];
	
	// reset the return card
	[[g_world gameState] setReturnCard:nil];
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
		DISPATCH_COMMAND3(RX_COMMAND_PLAY_LOCAL_SOUND, 8, 256, 0);
	else
		DISPATCH_COMMAND3(RX_COMMAND_PLAY_LOCAL_SOUND, 3, 256, 0);
	
	RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide direction:RXTransitionRight region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
	[controller queueTransition:transition];
	[transition release];
	
	DISPATCH_COMMAND0(RX_COMMAND_ENABLE_AUTOMATIC_SWAPS);
}

DEFINE_COMMAND(xaatrusbooknextpage) {
	uint16_t page = [[g_world gameState] unsignedShortForKey:@"aatruspage"];
	if (page < 10) {
		[[g_world gameState] setUnsignedShort:page + 1 forKey:@"aatruspage"];
		
		if (page == 1)
			DISPATCH_COMMAND3(RX_COMMAND_PLAY_LOCAL_SOUND, 8, 256, 0);
		else
			DISPATCH_COMMAND3(RX_COMMAND_PLAY_LOCAL_SOUND, 5, 256, 0);
		
		RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide direction:RXTransitionLeft region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
		[controller queueTransition:transition];
		[transition release];
		
		DISPATCH_COMMAND0(RX_COMMAND_ENABLE_AUTOMATIC_SWAPS);
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
		// GO MAGIC NUMBERS!
		NSPoint combination_display_origin = NSMakePoint(156.0f, 120.0f);
		NSPoint combination_sampling_origin = NSMakePoint(32.0f * 3, 0.0f);
		NSRect combination_base_rect = NSMakeRect(0.0f, 0.0f, 32.0f, 25.0f);
		
		[self _drawPictureWithID:13 archive:_archive displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y) samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
		combination_display_origin.x += combination_base_rect.size.width;
		
		[self _drawPictureWithID:14 archive:_archive displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y) samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
		combination_display_origin.x += combination_base_rect.size.width;
		
		[self _drawPictureWithID:15 archive:_archive displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y) samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
		combination_display_origin.x += combination_base_rect.size.width;
		
		[self _drawPictureWithID:16 archive:_archive displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y) samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
		combination_display_origin.x += combination_base_rect.size.width;
		
		[self _drawPictureWithID:17 archive:_archive displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y) samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
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
		DISPATCH_COMMAND3(RX_COMMAND_PLAY_LOCAL_SOUND, 9, 256, 0);
	else
		DISPATCH_COMMAND3(RX_COMMAND_PLAY_LOCAL_SOUND, 4, 256, 0);
	
	RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide direction:RXTransitionBottom region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
	[controller queueTransition:transition];
	[transition release];
	
	DISPATCH_COMMAND0(RX_COMMAND_ENABLE_AUTOMATIC_SWAPS);
}

DEFINE_COMMAND(xacathbooknextpage) {
	uint16_t page = [[g_world gameState] unsignedShortForKey:@"acathpage"];
	if (page < 49) {
		[[g_world gameState] setUnsignedShort:page + 1 forKey:@"acathpage"];
		
		if (page == 1)
			DISPATCH_COMMAND3(RX_COMMAND_PLAY_LOCAL_SOUND, 9, 256, 0);
		else
			DISPATCH_COMMAND3(RX_COMMAND_PLAY_LOCAL_SOUND, 6, 256, 0);
		
		RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide direction:RXTransitionTop region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
		[controller queueTransition:transition];
		[transition release];
		
		DISPATCH_COMMAND0(RX_COMMAND_ENABLE_AUTOMATIC_SWAPS);
	}
}

#pragma mark -
#pragma mark trap book

DEFINE_COMMAND(xtrapbookback) {	
	[self _returnFromJournal];
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
	// FIXME: actually generate a combination per game...
	if (page == 14) {
		// GO MAGIC NUMBERS!
		NSPoint combination_display_origin = NSMakePoint(240.0f, 285.0f);
		NSPoint combination_sampling_origin = NSMakePoint(32.0f * 4, 0.0f);
		NSRect combination_base_rect = NSMakeRect(0.0f, 0.0f, 32.0f, 24.0f);
		
		[self _drawPictureWithID:364 archive:_archive displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y) samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
		combination_display_origin.x += combination_base_rect.size.width;
		
		[self _drawPictureWithID:365 archive:_archive displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y) samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
		combination_display_origin.x += combination_base_rect.size.width;
		
		[self _drawPictureWithID:366 archive:_archive displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y) samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
		combination_display_origin.x += combination_base_rect.size.width;
		
		[self _drawPictureWithID:367 archive:_archive displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y) samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
		combination_display_origin.x += combination_base_rect.size.width;
		
		[self _drawPictureWithID:368 archive:_archive displayRect:NSOffsetRect(combination_base_rect, combination_display_origin.x, combination_display_origin.y) samplingRect:NSOffsetRect(combination_base_rect, combination_sampling_origin.x, combination_sampling_origin.y)];
	}
}

DEFINE_COMMAND(xblabopenbook) {
	[self _updateLabJournal];
}

DEFINE_COMMAND(xblabbookprevpage) {
	uint16_t page = [[g_world gameState] unsignedShortForKey:@"blabpage"];
	assert(page > 1);
	[[g_world gameState] setUnsignedShort:page - 1 forKey:@"blabpage"];
	
	DISPATCH_COMMAND3(RX_COMMAND_PLAY_LOCAL_SOUND, 22, 256, 0);
	
	RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide direction:RXTransitionRight region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
	[controller queueTransition:transition];
	[transition release];
	
	DISPATCH_COMMAND0(RX_COMMAND_ENABLE_AUTOMATIC_SWAPS);
}

DEFINE_COMMAND(xblabbooknextpage) {
	uint16_t page = [[g_world gameState] unsignedShortForKey:@"blabpage"];
	if (page < 22) {
		[[g_world gameState] setUnsignedShort:page + 1 forKey:@"blabpage"];
		
		DISPATCH_COMMAND3(RX_COMMAND_PLAY_LOCAL_SOUND, 23, 256, 0);
		
		RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide direction:RXTransitionLeft region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
		[controller queueTransition:transition];
		[transition release];
		
		DISPATCH_COMMAND0(RX_COMMAND_ENABLE_AUTOMATIC_SWAPS);
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
	
	DISPATCH_COMMAND3(RX_COMMAND_PLAY_LOCAL_SOUND, 12, 256, 0);
	
	RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide direction:RXTransitionRight region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
	[controller queueTransition:transition];
	[transition release];
	
	DISPATCH_COMMAND0(RX_COMMAND_ENABLE_AUTOMATIC_SWAPS);
}

DEFINE_COMMAND(xogehnbooknextpage) {
	uint16_t page = [[g_world gameState] unsignedShortForKey:@"ogehnpage"];
	if (page >= 13)
		return;

	[[g_world gameState] setUnsignedShort:page + 1 forKey:@"ogehnpage"];
	
	DISPATCH_COMMAND3(RX_COMMAND_PLAY_LOCAL_SOUND, 13, 256, 0);
	
	RXTransition* transition = [[RXTransition alloc] initWithType:RXTransitionSlide direction:RXTransitionLeft region:NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height)];
	[controller queueTransition:transition];
	[transition release];
	
	DISPATCH_COMMAND0(RX_COMMAND_ENABLE_AUTOMATIC_SWAPS);
}

#pragma mark -
#pragma mark rebel tunnel

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
	// this command sets the variable atemp to 1 if the specified icon is depressed, 0 otherwise; sets atemp to 2 if the icon cannot be depressed
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
		
		DISPATCH_COMMAND3(RX_COMMAND_PLAY_LOCAL_SOUND, 46, (short)kSoundGainDivisor, 1);
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
		DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 3);
		
		// play the mouth control lever movie
		DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 8);
	}
}

static const float k_jungle_elevator_trigger_magnitude = 16.0f;

DEFINE_COMMAND(xhandlecontrolup) {
	NSRect mouse_vector = [controller mouseVector];
	[controller setMouseCursor:2004];

	while ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:k_mouse_tracking_loop_period]] && isfinite(mouse_vector.size.width)) {
		if (mouse_vector.size.height < 0.0f && fabsf(mouse_vector.size.height) >= k_jungle_elevator_trigger_magnitude) {
			// play the switch down movie
			DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 1);
			
			// play the going down movie
			DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 2);
			
			// go to card jspit 392
			DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, 392);
			
			// we're all done
			break;
		}
		
		[controller setMouseCursor:2004];
		mouse_vector = [controller mouseVector];
	}
}

DEFINE_COMMAND(xhandlecontrolmid) {
	NSRect mouse_vector = [controller mouseVector];
	[controller setMouseCursor:2004];
	
	while ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:k_mouse_tracking_loop_period]] && isfinite(mouse_vector.size.width)) {
		if (mouse_vector.size.height >= k_jungle_elevator_trigger_magnitude) {
			// play the switch up movie
			DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 7);
			
			[self _handleJungleElevatorMouth];
			
			// play the going up movie
			DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 5);
			
			// go to card jspit 361
			DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, 361);
			
			// we're all done
			break;
		} else if (mouse_vector.size.height < 0.0f && fabsf(mouse_vector.size.height) >= k_jungle_elevator_trigger_magnitude) {
			// play the switch up movie
			DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 6);
			
			[self _handleJungleElevatorMouth];
			
			// play the going down movie
			DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 4);
			
			// go to card jspit 395
			DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, 395);
			
			// we're all done
			break;
		}
		
		[controller setMouseCursor:2004];
		mouse_vector = [controller mouseVector];
	}
}

DEFINE_COMMAND(xhandlecontroldown) {
	NSRect mouse_vector = [controller mouseVector];
	[controller setMouseCursor:2004];

	while ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:k_mouse_tracking_loop_period]] && isfinite(mouse_vector.size.width)) {
		if (mouse_vector.size.height >= k_jungle_elevator_trigger_magnitude) {
			// play the switch up movie
			DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 1);
			
			// play the going up movie
			DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 2);
			
			// go to card jspit 392
			DISPATCH_COMMAND1(RX_COMMAND_GOTO_CARD, 392);
			
			// we're all done
			break;
		}
		
		[controller setMouseCursor:2004];
		mouse_vector = [controller mouseVector];
	}
}

#pragma mark -
#pragma mark boiler central

DEFINE_COMMAND(xvalvecontrol) {
	uint16_t valve_state = [[g_world gameState] unsignedShortForKey:@"bvalve"];
	
	NSRect mouse_vector = [controller mouseVector];
	[controller setMouseCursor:2004];
	
	while ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:k_mouse_tracking_loop_period]] && isfinite(mouse_vector.size.width)) {
		float theta = 180.0f * atan2f(mouse_vector.size.height, mouse_vector.size.width) * M_1_PI;
		float r = sqrtf((mouse_vector.size.height * mouse_vector.size.height) + (mouse_vector.size.width * mouse_vector.size.width));
		
		switch (valve_state) {
			case 0:
				if (theta <= -90.0f && theta >= -150.0f && r >= 40.0f) {
					valve_state = 1;
					[[g_world gameState] setUnsignedShort:valve_state forKey:@"bvalve"];
					DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 2);
					DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
				}
				break;
			case 1:
				if (theta <= 80.0f && theta >= -10.0f && r >= 40.0f) {
					valve_state = 0;
					[[g_world gameState] setUnsignedShort:valve_state forKey:@"bvalve"];
					DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 3);
					DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
				} else if ((theta <= -60.0f || theta >= 160.0f) && r >= 20.0f) {
					valve_state = 2;
					[[g_world gameState] setUnsignedShort:valve_state forKey:@"bvalve"];
					DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 1);
					DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
				}
				break;
			case 2:
				if (theta <= 30.0f && theta >= -30.0f && r >= 20.0f) {
					valve_state = 1;
					[[g_world gameState] setUnsignedShort:valve_state forKey:@"bvalve"];
					DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 4);
					DISPATCH_COMMAND0(RX_COMMAND_REFRESH);
				}
				break;
		}
		
		// if we did hide the mouse, it means we played one of the valve movies; if so, break out of the mouse tracking loop
		if (_did_hide_mouse) {
			break;
		}		
		
		[controller setMouseCursor:2004];
		mouse_vector = [controller mouseVector];
	}
}

DEFINE_COMMAND(xbchipper) {
	[controller setMouseCursor:2004];

	uint16_t valve_state = [[g_world gameState] unsignedShortForKey:@"bvalve"];
	if (valve_state != 2)
		return;
	
	DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 2);
	// FIXME: need to disable that movie code
}

DEFINE_COMMAND(xbupdateboiler) {
	DISPATCH_COMMAND1(RX_COMMAND_PLAY_MOVIE_BLOCKING, 11);
}

DEFINE_COMMAND(xbchangeboiler) {
	uint16_t heat = [[g_world gameState] unsignedShortForKey:@"bheat"];
	uint16_t water = [[g_world gameState] unsignedShortForKey:@"bblrwtr"];
	uint16_t platform = [[g_world gameState] unsignedShortForKey:@"bblrgrt"];
	
	if (argv[0] == 2) {		
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
}

DEFINE_COMMAND(xsoundplug) {
	// this needs to activate the correct SLST record based on the state of the boiler and the card
}

@end
