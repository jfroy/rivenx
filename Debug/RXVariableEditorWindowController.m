//
//  RXVariableEditorWindowController.m
//  rivenx
//
//  Created by Jean-Francois Roy on 13/01/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "RXVariableEditorWindowController.h"


@implementation RXVariableEditorWindowController

- (id)initWithVariables:(NSMutableDictionary*)vars title:(NSString*)title {
    self = [super initWithWindowNibName:@"VariableEditor"];
    if (!self) return nil;
    
    _title = [title copy];
    _varNames = [NSMutableArray new];
    _varValues = [NSMutableArray new];
    
    return self;
}

- (void)dealloc {
    [_title release];
    [_varNames release];
    [_varValues release];
    
    [super dealloc];
}

- (void)windowDidLoad {
    
}

@end
