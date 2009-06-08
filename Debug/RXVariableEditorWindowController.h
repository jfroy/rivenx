//
//  RXVariableEditorWindowController.h
//  rivenx
//
//  Created by Jean-Francois Roy on 13/01/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface RXVariableEditorWindowController : NSWindowController {
    IBOutlet NSTableView* _variableTable;
    
@private
    NSString* _title;
    
    NSMutableArray* _varNames;
    NSMutableArray* _varValues;
}

- (id)initWithVariables:(NSMutableDictionary*)vars title:(NSString*)title;

@end
