//
//  RXScriptCompiler.m
//  rivenx
//
//  Created by Jean-Francois Roy on 9/30/09.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import "RXScriptCompiler.h"


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

- (NSDictionary*)compiledScript {
    if (_ops)
        return [_ops script];
    
    // compile
    
    return [_ops script];
}

- (void)setCompiledScript:(NSDictionary*)script {
    [_ops release];
    _ops = [[RXScriptOpcodeStream alloc] initWithScript:script];
    
    [_decompiled_script release];
    _decompiled_script = nil;
}

- (NSMutableArray*)decompiledScript {
    if (_decompiled_script)
        return [[_decompiled_script mutableCopy] autorelease];
    
    // decompile
    
    return [[_decompiled_script mutableCopy] autorelease];
}

- (void)setDecompiledScript:(NSArray*)script {
    [_ops release];
    _ops = nil;
    
    [_decompiled_script release];
    _decompiled_script = [script copy];
}

@end
