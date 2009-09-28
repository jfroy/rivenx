//
//  RXScriptOpcodeStream.m
//  rivenx
//
//  Created by Jean-Francois Roy on 15/07/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import "Engine/RXScriptOpcodeStream.h"
#import "Engine/RXScriptCommandAliases.h"
#import "Engine/RXScriptDecoding.h"


@implementation RXScriptOpcodeStream

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithScript:(NSDictionary*)program {
    [program retain];
    
    self = [self initWithScriptBuffer:[[program objectForKey:RXScriptProgramKey] bytes]
                          opcodeCount:[[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue]];
    if (!self) {
        [program release];
        return nil;
    }
    
    _program_dict = program;
    
    return self;
}

- (id)initWithScriptBuffer:(uint16_t const*)pbuf opcodeCount:(uint16_t)op_count {
    self = [super init];
    if (!self)
        return nil;
    
    _program = pbuf;
    _opcode_count = op_count;
    
    [self reset];
    
    return self;
}

- (void)dealloc {
    [_program_dict release];
    [_substream release];
    [super dealloc];
}

- (id)delegate {
    return _delegate;
}

- (void)setDelegate:(id)delegate {
    _delegate = delegate;
}

- (void)reset {
    [_substream release];
    _substream = nil;
    case_index = 0;
    
    _pbuf = _program;
    pc = 0;
}

- (rx_opcode_t*)nextOpcode {
    if (_substream) {
        rx_opcode_t* opcode = [_substream nextOpcode];
        if (opcode)
            return opcode;
        
        // end of a branch case block
        
        _case_pbuf = _substream->_pbuf;
        case_index++;
        
        [_substream release];
        _substream = nil;
        
        return [self nextOpcode];
    }
    
    if (pc == _opcode_count)
        return NULL;
    
    if (*_pbuf == RX_COMMAND_BRANCH) {
        uint16_t case_count = *(_pbuf + 3);
        
        // entering a branch block
        if (case_index == 0) {
            _case_pbuf = BUFFER_OFFSET(_pbuf, 8); // argc, variable ID, case count
            if ([_delegate respondsToSelector:@selector(opcodeStream:willEnterBranchForVariable:)])
                [_delegate opcodeStream:self willEnterBranchForVariable:*BUFFER_OFFSET(_pbuf, 2)];
        }
        
        // exiting a branch block
        if (case_index == case_count) {
            case_index = 0;
            
            _pbuf = _case_pbuf;
            pc++;
            
            if ([_delegate respondsToSelector:@selector(opcodeStreamWillExitBranch:)])
                [_delegate opcodeStreamWillExitBranch:self];
            
            return [self nextOpcode];
        }
        
        _substream = [[RXScriptOpcodeStream alloc] initWithScriptBuffer:(_case_pbuf + 2) opcodeCount:*(_case_pbuf + 1)];
        [_substream setDelegate:_delegate];
        
        if ([_delegate respondsToSelector:@selector(opcodeStream:willEnterBranchCaseForValue:)])
            [_delegate opcodeStream:self willEnterBranchCaseForValue:*_case_pbuf];
        
        return [self nextOpcode];
    } else {
        _opcode.command = *_pbuf;
        _opcode.argc = *(_pbuf + 1);
        _opcode.arguments = _pbuf + 2;
        
        _pbuf = BUFFER_OFFSET(_pbuf, 4 + _opcode.argc * sizeof(uint16_t));
        pc++;
        
        return &_opcode;
    }
}

@end
