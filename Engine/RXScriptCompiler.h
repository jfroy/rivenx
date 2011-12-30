//
//  RXScriptCompiler.h
//  rivenx
//
//  Created by Jean-Francois Roy on 9/30/09.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "Engine/RXScriptOpcodeStream.h"
#import "NSArray+RXArrayAdditions.h"


#define RX_VAR_NAME_EQ(var, name) [[_parent varNameAtIndex:(var)] isEqualToString:(name)]

#define RX_OPCODE_COMMAND_EQ(opcode, command) [[(opcode) objectForKey:@"command"] unsignedShortValue] == (command)
#define RX_OPCODE_ARG(opcode, i) [[[(opcode) objectForKey:@"args"] objectAtIndexIfAny:(i)] unsignedShortValue]
#define RX_OPCODE_SET_ARG(opcode, i, value) [[(opcode) objectForKey:@"args"] replaceObjectAtIndex:(i) withObject:[NSNumber numberWithUnsignedShort:(value)]]

#define RX_BRANCH_VAR_NAME_EQ(branch, name) [[_parent varNameAtIndex:[[(branch) objectForKey:@"variable"] unsignedShortValue]] isEqualToString:(name)]
#define RX_CASE_VAL_EQ(case, value) [[(case) objectForKey:@"value"] unsignedShortValue] == (value)

@interface RXScriptCompiler : NSObject
{
    RXScriptOpcodeStream* _ops;
    NSMutableArray* _decompiled_script;
    
    NSMutableArray* _current_block;
    NSMutableArray* _block_stack;
    NSMutableArray* _cases_stack;
}

- (id)initWithCompiledScript:(NSDictionary*)script;
- (id)initWithDecompiledScript:(NSArray*)script;

- (NSDictionary*)compiledScript;
- (void)setCompiledScript:(NSDictionary*)script;

- (NSMutableArray*)decompiledScript;
- (void)setDecompiledScript:(NSArray*)script;

@end
