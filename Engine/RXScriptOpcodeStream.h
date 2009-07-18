//
//  RXScriptOpcodeStream.h
//  rivenx
//
//  Created by Jean-Francois Roy on 15/07/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>


typedef struct {
    uint16_t command;
    uint16_t argc;
    uint16_t const* arguments;
} rx_opcode_t;

@interface RXScriptOpcodeStream : NSObject {
    NSDictionary* _program;
    uint16_t _opcode_count;
    RXScriptOpcodeStream* _substream;
    
    rx_opcode_t _opcode;
    
    uint16_t const* _pbuf;
    uint16_t pc;
    
    uint16_t const* _case_pbuf;
    uint16_t case_index;
}

- (id)initWithProgram:(NSDictionary*)program;

- (void)reset;
- (rx_opcode_t*)nextOpcode;

@end
