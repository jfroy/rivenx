//
//  RXScriptCompiler.m
//  rivenx
//
//  Created by Jean-Francois Roy on 9/30/09.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import "Engine/RXScriptCompiler.h"
#import "Engine/RXScriptCommandAliases.h"
#import "Engine/RXScriptDecoding.h"


@implementation RXScriptCompiler

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithCompiledScript:(NSDictionary*)script {
    self = [super init];
    if (!self)
        return nil;
    
    [self setCompiledScript:script];
    if (!_ops) {
        [self release];
        return  nil;
    }
    
    return self;
}

- (id)initWithDecompiledScript:(NSArray*)script {
    self = [super init];
    if (!self)
        return nil;
    
    [self setDecompiledScript:script];
    if (!_decompiled_script) {
        [self release];
        return  nil;
    }
    
    return self;
}

- (void)dealloc {
    [_ops release];
    [_decompiled_script release];
    [super dealloc];
}

- (void)_compileBlock:(NSArray*)block inBuffer:(NSMutableData*)pbuf {
    NSEnumerator* iter_opcode = [block objectEnumerator];
    NSDictionary* opcode = nil;
    while ((opcode = [iter_opcode nextObject])) {
        assert([opcode objectForKey:@"command"]);
        uint16_t temp = [[opcode objectForKey:@"command"] unsignedShortValue];
        
        if (temp == RX_COMMAND_BRANCH) {
            [pbuf appendBytes:&temp length:sizeof(uint16_t)];
            
            temp = 2;
            [pbuf appendBytes:&temp length:sizeof(uint16_t)];
            
            assert([opcode objectForKey:@"variable"]);
            temp = [[opcode objectForKey:@"variable"] unsignedShortValue];
            [pbuf appendBytes:&temp length:sizeof(uint16_t)];
            
            NSArray* cases = [opcode objectForKey:@"cases"];
            assert(cases);
            
            temp = [cases count];
            [pbuf appendBytes:&temp length:sizeof(uint16_t)];
            
            NSEnumerator* iter_cases = [cases objectEnumerator];
            NSDictionary* c = nil;
            while ((c = [iter_cases nextObject])) {
                assert([c objectForKey:@"value"]);
                temp = [[c objectForKey:@"value"] unsignedShortValue];
                [pbuf appendBytes:&temp length:sizeof(uint16_t)];
                
                NSArray* block = [c objectForKey:@"block"];
                assert(block);
                
                temp = [block count];
                [pbuf appendBytes:&temp length:sizeof(uint16_t)];
                
                [self _compileBlock:block inBuffer:pbuf];
            }
        } else {
            NSArray* args = [opcode objectForKey:@"args"];
            assert(args);
            
            [pbuf appendBytes:&temp length:sizeof(uint16_t)];
            
            uint16_t argc = [args count];
            [pbuf appendBytes:&argc length:sizeof(uint16_t)];
            
            for (uint16_t argi = 0; argi < argc; argi++) {
                temp = [[args objectAtIndex:argi] unsignedShortValue];
                [pbuf appendBytes:&temp length:sizeof(uint16_t)];
            }
        }
    }
}

- (NSDictionary*)compiledScript {
    if (_ops)
        return [_ops script];
    
    // compile
    NSMutableData* pbuf = [[NSMutableData alloc] init];
    [self _compileBlock:_decompiled_script inBuffer:pbuf];
    
    NSDictionary* script = [NSDictionary dictionaryWithObjectsAndKeys:
        pbuf, RXScriptProgramKey,
        [NSNumber numberWithUnsignedShort:[_decompiled_script count]], RXScriptOpcodeCountKey,
        nil];
    [pbuf release];
    
    _ops = [[RXScriptOpcodeStream alloc] initWithScript:script];
    return [_ops script];
}

- (void)setCompiledScript:(NSDictionary*)script {
    [script retain];
    
    [_ops release];
    _ops = [[RXScriptOpcodeStream alloc] initWithScript:script];
    [_ops setDelegate:self];
    
    [script release];
    
    [_decompiled_script release];
    _decompiled_script = nil;
}

- (NSMutableArray*)decompiledScript {
    if (_decompiled_script)
        return [[_decompiled_script mutableCopy] autorelease];
    
    // decompile
    _decompiled_script = [[NSMutableArray alloc] init];
    
    _cases_stack = [[NSMutableArray alloc] init];
    _block_stack = [[NSMutableArray alloc] init];
    
    [_block_stack addObject:_decompiled_script];
    _current_block = _decompiled_script;
    
    [_ops reset];
    
    rx_opcode_t* op = NULL;
    while ((op = [_ops nextOpcode])) {
        NSMutableArray* args = [NSMutableArray array];
        for (uint16_t i = 0; i < op->argc; i++)
            [args addObject:[NSNumber numberWithUnsignedShort:op->arguments[i]]];
        
        assert(_current_block);
        [_current_block addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   [NSNumber numberWithUnsignedShort:op->command], @"command",
                                   args, @"args",
                                   nil]];
    }
    
    _current_block = nil;
    
    [_block_stack release];
    _block_stack = nil;
    
    [_cases_stack release];
    _cases_stack = nil;
    
    return [[_decompiled_script mutableCopy] autorelease];
}

- (void)setDecompiledScript:(NSArray*)script {
    [_ops release];
    _ops = nil;
    
    [_decompiled_script release];
    _decompiled_script = [script copy];
}

- (void)opcodeStream:(RXScriptOpcodeStream*)stream willEnterBranchForVariable:(uint16_t)var {
    NSMutableArray* cases = [NSMutableArray array];
    
    [_current_block addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
                               [NSNumber numberWithUnsignedShort:RX_COMMAND_BRANCH], @"command",
                               [NSNumber numberWithUnsignedShort:var], @"variable",
                               cases, @"cases",
                               nil]];
    
    [_cases_stack addObject:cases];
    [_block_stack addObject:_current_block];
    
    _current_block = nil;
}

- (void)opcodeStreamWillExitBranch:(RXScriptOpcodeStream*)stream {
    // pop the cases dictionary off the cases stack
    assert([_cases_stack count] > 0);
    [_cases_stack removeLastObject];
    
    // pop to current block off the block stack and set _current_block to the top of the stack
    assert([_block_stack count] > 1);
    [_block_stack removeLastObject];
    
    _current_block = [_block_stack lastObject];
}

- (void)opcodeStream:(RXScriptOpcodeStream*)stream willEnterBranchCaseForValue:(uint16_t)value {
    // create a new block array for the branch case
    _current_block = [NSMutableArray array];
    
    NSMutableArray* cases = [_cases_stack lastObject];
    [cases addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
        _current_block, @"block",
        [NSNumber numberWithUnsignedShort:value], @"value",
        nil]];
}

@end
