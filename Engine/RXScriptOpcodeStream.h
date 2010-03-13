//
//  RXScriptOpcodeStream.h
//  rivenx
//
//  Created by Jean-Francois Roy on 15/07/2009.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>


typedef struct {
    uint16_t command;
    uint16_t argc;
    uint16_t const* arguments;
} rx_opcode_t;

@interface RXScriptOpcodeStream : NSObject {
    NSDictionary* _script;
    
    uint16_t const* _program;
    uint16_t _opcode_count;
    RXScriptOpcodeStream* _substream;
    
    rx_opcode_t _opcode;
    
    uint16_t const* _pbuf;
    uint16_t pc;
    
    uint16_t const* _case_pbuf;
    uint16_t case_index;
    
    id _delegate;
}

- (id)initWithScript:(NSDictionary*)script;
- (id)initWithScriptBuffer:(uint16_t const*)pbuf opcodeCount:(uint16_t)op_count;

- (id)delegate;
- (void)setDelegate:(id)delegate;

- (NSDictionary*)script;

- (void)reset;
- (rx_opcode_t*)nextOpcode;

@end

@interface NSObject(RXScriptOpcodeStreamDelegate)

- (void)opcodeStream:(RXScriptOpcodeStream*)stream willEnterBranchForVariable:(uint16_t)var;
- (void)opcodeStreamWillExitBranch:(RXScriptOpcodeStream*)stream;
- (void)opcodeStream:(RXScriptOpcodeStream*)stream willEnterBranchCaseForValue:(uint16_t)value;

@end
