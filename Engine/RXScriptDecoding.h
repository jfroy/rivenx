//
//  RXScriptDecoding.h
//  rivenx
//
//  Created by Jean-Francois Roy on 31/01/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sys/cdefs.h>

__BEGIN_DECLS

enum {
	kScriptTypeMouseDown = 0,
	kScriptTypeUnknown1,
	kScriptTypeMouseUp,
	kScriptTypeUnknown3,
	kScriptTypeMouseInside,
	kScriptTypeMouseExited,
	kScriptTypeCardPrepare,
	kScriptTypeCardStopRendering,
	kScriptTypeUnknown8,
	kScriptTypeStartRendering,
	kScriptTypeScreenUpdate,
};

extern NSString* const RXMouseDownScriptKey;
extern NSString* const RXUnknown1ScriptKey;
extern NSString* const RXMouseUpScriptKey;
extern NSString* const RXUnknown3ScriptKey;
extern NSString* const RXMouseInsideScriptKey;
extern NSString* const RXMouseExitedScriptKey;
extern NSString* const RXCardPrepareScriptKey;
extern NSString* const RXCardStopRenderingScriptKey;
extern NSString* const RXUnknown8ScriptKey;
extern NSString* const RXStartRenderingScriptKey;
extern NSString* const RXScreenUpdateScriptKey;

extern NSString* const RXScriptProgramKey;
extern NSString* const RXScriptOpcodeCountKey;

size_t rx_compute_riven_script_length(const void* script, uint16_t command_count, bool byte_swap);
NSDictionary* rx_decode_riven_script(const void* script, uint32_t* script_length);

uint16_t rx_get_riven_script_opcode(const void* script, uint16_t command_count, uint16_t opcode_index);

__END_DECLS
