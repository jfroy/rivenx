//
//  RXScriptDecoding.h
//  rivenx
//
//  Created by Jean-Francois Roy on 31/01/2009.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"
#import <sys/cdefs.h>

__BEGIN_DECLS

enum {
    kScriptTypeMouseDown = 0,
    kScriptTypeMouseStillDown,
    kScriptTypeMouseUp,
    kScriptTypeUnknown3,
    kScriptTypeMouseInside,
    kScriptTypeMouseExited,
    kScriptTypeCardOpen,
    kScriptTypeCardClose,
    kScriptTypeIdle,
    kScriptTypeStartRendering,
    kScriptTypeScreenUpdate,
};

extern NSString* const RXMouseDownScriptKey;
extern NSString* const RXMouseStillDownScriptKey;
extern NSString* const RXMouseUpScriptKey;
extern NSString* const RXUnknown3ScriptKey;
extern NSString* const RXMouseInsideScriptKey;
extern NSString* const RXMouseExitedScriptKey;
extern NSString* const RXCardOpenScriptKey;
extern NSString* const RXCardCloseScriptKey;
extern NSString* const RXIdleScriptKey;
extern NSString* const RXStartRenderingScriptKey;
extern NSString* const RXScreenUpdateScriptKey;

extern NSString* const RXScriptProgramKey;
extern NSString* const RXScriptOpcodeCountKey;

size_t rx_compute_riven_script_length(const void* script, uint16_t command_count, bool byte_swap);
NSDictionary* rx_decode_riven_script(const void* script, uint32_t* script_length);

uint16_t rx_get_riven_script_opcode(const void* script, uint16_t command_count, uint16_t opcode_index, uint32_t* opcode_offset);
uint16_t rx_get_riven_script_case_opcode_count(const void* switch_opcode, uint16_t case_index, uint32_t* case_program_offset);

__END_DECLS
