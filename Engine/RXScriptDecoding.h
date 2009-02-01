//
//  RXScriptDecoding.h
//  rivenx
//
//  Created by Jean-Francois Roy on 31/01/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

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

NSString* const RXMouseDownScriptKey;
NSString* const RXUnknown1ScriptKey;
NSString* const RXMouseUpScriptKey;
NSString* const RXUnknown3ScriptKey;
NSString* const RXMouseInsideScriptKey;
NSString* const RXMouseExitedScriptKey;
NSString* const RXCardPrepareScriptKey;
NSString* const RXCardStopRenderingScriptKey;
NSString* const RXUnknown8ScriptKey;
NSString* const RXStartRenderingScriptKey;
NSString* const RXScreenUpdateScriptKey;

size_t rx_compute_riven_script_length(const void* script, uint16_t command_count, bool byte_swap);
NSArray* rx_decode_riven_script(const void* script, uint32_t* script_length);
