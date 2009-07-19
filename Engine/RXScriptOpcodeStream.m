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
    self = [super init];
    if (!self)
        return nil;
    
    _program = [program retain];
    _opcode_count = [[_program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue];
    
    [self reset];
    
    return self;
}

- (void)dealloc {
    [_program release];
    [_substream release];
    [super dealloc];
}

- (void)reset {
    [_substream release];
    _substream = nil;
    case_index = 0;
    
    _pbuf = [[_program objectForKey:RXScriptProgramKey] bytes];
    pc = 0;
}

- (rx_opcode_t*)nextOpcode {
    if (_substream) {
        rx_opcode_t* opcode = [_substream nextOpcode];
        if (opcode)
            return opcode;
        
        [_substream release];
        _substream = nil;
        
        return [self nextOpcode];
    }
    
    if (pc == _opcode_count)
        return NULL;
    
    if (*_pbuf == RX_COMMAND_BRANCH) {
        uint16_t case_count = *(_pbuf + 3);
        
        if (case_index == case_count) {
            case_index = 0;
            
            _pbuf = _case_pbuf;
            pc++;
            
            return [self nextOpcode];
        } else if (case_index == 0)
            _case_pbuf = BUFFER_OFFSET(_pbuf, 8); // argc, variable ID, case count
        
        size_t subprogram_size = rx_compute_riven_script_length((_case_pbuf + 2), *(_case_pbuf + 1), false) + 4;
        NSDictionary* subprogram = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSData dataWithBytesNoCopy:(void*)(_case_pbuf + 2) length:subprogram_size freeWhenDone:NO], RXScriptProgramKey,
            [NSNumber numberWithUnsignedShort:*(_case_pbuf + 1)], RXScriptOpcodeCountKey,
            nil];
        _substream = [[RXScriptOpcodeStream alloc] initWithScript:subprogram];
        
        _case_pbuf = BUFFER_OFFSET(_case_pbuf, subprogram_size);
        case_index++;
        
        return [_substream nextOpcode];
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
