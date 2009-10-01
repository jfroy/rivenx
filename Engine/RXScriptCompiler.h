//
//  RXScriptCompiler.h
//  rivenx
//
//  Created by Jean-Francois Roy on 9/30/09.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "Engine/RXScriptOpcodeStream.h"


@interface RXScriptCompiler : NSObject {
    RXScriptOpcodeStream* _ops;
    NSArray* _decompiled_script;
}

- (id)initWithCompiledScript:(NSDictionary*)script;
- (id)initWithDecompiledScript:(NSArray*)script;

- (NSDictionary*)compiledScript;
- (void)setCompiledScript:(NSDictionary*)script;

- (NSMutableArray*)decompiledScript;
- (void)setDecompiledScript:(NSArray*)script;

@end
