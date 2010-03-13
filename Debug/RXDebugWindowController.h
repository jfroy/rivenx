//
//  RXDebugWindowController.h
//  rivenx
//
//  Created by Jean-Francois Roy on 27/01/2006.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//


#import <Cocoa/Cocoa.h>


@interface RXDebugWindowController : NSWindowController {
    IBOutlet NSTextView* consoleView;
    NSFont* _consoleFont;
    
    uint16_t _trip;
}

- (IBAction)runPythonCmd:(id)sender;

@end
