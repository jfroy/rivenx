//
//  RXScriptDecoding.m
//  rivenx
//
//  Created by Jean-Francois Roy on 31/01/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import "RXScriptDecoding.h"


NSString* const RXMouseDownScriptKey = @"mouse down";
NSString* const RXMouseStillDownScriptKey = @"mouse still down";
NSString* const RXMouseUpScriptKey = @"mouse up";
NSString* const RXUnknown3ScriptKey = @"unknown 3";
NSString* const RXMouseInsideScriptKey = @"mouse inside";
NSString* const RXMouseExitedScriptKey = @"mouse exited";
NSString* const RXCardOpenScriptKey = @"open card";
NSString* const RXCardCloseScriptKey = @"close card";
NSString* const RXIdleScriptKey = @"idle";
NSString* const RXStartRenderingScriptKey = @"start rendering";
NSString* const RXScreenUpdateScriptKey = @"screen update";

NSString* const RXScriptProgramKey = @"program";
NSString* const RXScriptOpcodeCountKey = @"opcode count";

static NSString* script_keys_array[11] = {
    @"mouse down",
    @"unknown 1",
    @"mouse up",
    @"unknown 3",
    @"mouse inside",
    @"mouse exited",
    @"open card",
    @"close card",
    @"idle",
    @"start rendering",
    @"screen update"
};

size_t rx_compute_riven_script_length(const void* script, uint16_t command_count, bool byte_swap) {
    size_t scriptOffset = 0;
    for (uint16_t currentCommandIndex = 0; currentCommandIndex < command_count; currentCommandIndex++) {
        // command, argument count, arguments (all shorts)
        uint16_t commandNumber = *(const uint16_t*)BUFFER_OFFSET(script, scriptOffset);
        if (byte_swap)
            commandNumber = CFSwapInt16BigToHost(commandNumber);
        scriptOffset += 2;
        
        uint16_t argumentCount = *(const uint16_t*)BUFFER_OFFSET(script, scriptOffset);
        if (byte_swap)
            argumentCount = CFSwapInt16BigToHost(argumentCount);
        size_t argumentsOffset = 2 * (argumentCount + 1);
        scriptOffset += argumentsOffset;
        
        // need to do extra processing for command 8
        if (commandNumber == 8) {
            // arg 0 is the variable, arg 1 is the number of cases
            uint16_t caseCount = *(const uint16_t*)BUFFER_OFFSET(script, scriptOffset - argumentsOffset + 4);
            if (byte_swap)
                caseCount = CFSwapInt16BigToHost(caseCount);
            
            uint16_t currentCaseIndex = 0;
            for (; currentCaseIndex < caseCount; currentCaseIndex++) {
                // case variable value
                scriptOffset += 2;
                
                uint16_t caseCommandCount = *(const uint16_t*)BUFFER_OFFSET(script, scriptOffset);
                if (byte_swap)
                    caseCommandCount = CFSwapInt16BigToHost(caseCommandCount);
                scriptOffset += 2;
                
                size_t caseCommandListLength = rx_compute_riven_script_length(BUFFER_OFFSET(script, scriptOffset), caseCommandCount, byte_swap);
                scriptOffset += caseCommandListLength;
            }
        }
    }
    
    return scriptOffset;
}

NSDictionary* rx_decode_riven_script(const void* script, uint32_t* script_length) {
    // WARNING: THIS METHOD ASSUMES THE INPUT SCRIPT IS IN BIG ENDIAN
    
    // a script is composed of several events
    uint16_t eventCount = CFSwapInt16BigToHost(*(const uint16_t*)script);
    uint32_t scriptOffset = 2;
    
    // one array of Riven programs per event type
    uint32_t eventTypeCount = sizeof(script_keys_array) / sizeof(NSString*);
    uint16_t currentEventIndex = 0;
    NSMutableArray** eventProgramsPerType = (NSMutableArray**)malloc(sizeof(NSMutableArray*) * eventTypeCount);
    for (; currentEventIndex < eventTypeCount; currentEventIndex++)
        eventProgramsPerType[currentEventIndex] = [[NSMutableArray alloc] initWithCapacity:eventCount];
    
    // process the programs
    for (currentEventIndex = 0; currentEventIndex < eventCount; currentEventIndex++) {
        // event type, command count
        uint16_t eventCode = CFSwapInt16BigToHost(*(const uint16_t*)BUFFER_OFFSET(script, scriptOffset));
        scriptOffset += 2;
        uint16_t commandCount = CFSwapInt16BigToHost(*(const uint16_t*)BUFFER_OFFSET(script, scriptOffset));
        scriptOffset += 2;
        
        // program length
        size_t programLength = rx_compute_riven_script_length(BUFFER_OFFSET(script, scriptOffset), commandCount, true);
        
        // allocate a storage buffer for the program and swap it if needed
        uint16_t* programStore = (uint16_t*)malloc(programLength);
        memcpy(programStore, BUFFER_OFFSET(script, scriptOffset), programLength);
#if defined(__LITTLE_ENDIAN__)
        uint32_t shortCount = programLength / 2;
        while (shortCount > 0) {
            programStore[shortCount - 1] = CFSwapInt16BigToHost(programStore[shortCount - 1]);
            shortCount--;
        }
#endif
        
        // store the program in an NSData object
        NSData* program = [[NSData alloc] initWithBytesNoCopy:programStore length:programLength freeWhenDone:YES];
        scriptOffset += programLength;
        
        // program descriptor
        NSDictionary* programDescriptor = [[NSDictionary alloc] initWithObjectsAndKeys:program, RXScriptProgramKey,
            [NSNumber numberWithUnsignedShort:commandCount], RXScriptOpcodeCountKey,
            nil];
        assert(eventCode < eventTypeCount);
        [eventProgramsPerType[eventCode] addObject:programDescriptor];
        
        [program release];
        [programDescriptor release];
    }
    
    // each event key holds an array of programs
    NSDictionary* scriptDictionary = [[NSDictionary alloc] initWithObjects:eventProgramsPerType forKeys:script_keys_array count:eventTypeCount];
    
    // release the program arrays now that they're in the dictionary
    for (currentEventIndex = 0; currentEventIndex < eventTypeCount; currentEventIndex++)
        [eventProgramsPerType[currentEventIndex] release];
    
    // release the program array array.
    free(eventProgramsPerType);
    
    // return total script length and script dictionary
    if (script_length)
        *script_length = scriptOffset;
    return scriptDictionary;
}

uint16_t rx_get_riven_script_opcode(const void* script, uint16_t command_count, uint16_t opcode_index, uint32_t* opcode_offset) {
    assert(opcode_index < command_count);
    
    size_t offset = 0;
    for (uint16_t index = 0; index < command_count; index++) {
        // command, argument count, arguments (all shorts)
        uint16_t opcode = *(const uint16_t*)BUFFER_OFFSET(script, offset);
        offset += 2;
        
        // is this the one?
        if (index == opcode_index) {
            if (opcode_offset)
                *opcode_offset = offset - 2;
            return opcode;
        }
        
        uint16_t argc = *(const uint16_t*)BUFFER_OFFSET(script, offset);
        size_t arg_offset = 2 * (argc + 1);
        offset += arg_offset;
        
        // need to do extra processing for command 8
        if (opcode == 8) {
            // arg 0 is the variable, arg 1 is the number of cases
            uint16_t case_count = *(const uint16_t*)BUFFER_OFFSET(script, offset - arg_offset + 4);
            
            uint16_t case_index = 0;
            for (; case_index < case_count; case_index++) {
                // case variable value
                offset += 2;
                
                uint16_t case_command_count = *(const uint16_t*)BUFFER_OFFSET(script, offset);
                offset += 2;
                
                size_t case_size = rx_compute_riven_script_length(BUFFER_OFFSET(script, offset), case_command_count, false);
                offset += case_size;
            }
        }
    }
    
    // should never reach this line
    return 0;
}

uint16_t rx_get_riven_script_case_opcode_count(const void* switch_opcode, uint16_t case_index, uint32_t* case_program_offset) {
    assert(*(uint16_t*)switch_opcode == 8);
    
    uint16_t case_count = *(uint16_t*)BUFFER_OFFSET(switch_opcode, 6);
    assert(case_index < case_count);
    
    size_t offset = 8;
    for (uint16_t current_case = 0; current_case < case_count; current_case++) {
        // case variable value
        offset += 2;
        
        uint16_t case_command_count = *(const uint16_t*)BUFFER_OFFSET(switch_opcode, offset);
        offset += 2;
        
        // is this the one?
        if (current_case == case_index) {
            if (case_program_offset)
                *case_program_offset = offset;
            return case_command_count;
        }
        
        size_t case_size = rx_compute_riven_script_length(BUFFER_OFFSET(switch_opcode, offset), case_command_count, false);
        offset += case_size;
    }
    
    // should never reach this line
    return 0;
}
