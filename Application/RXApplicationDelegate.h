//
//  RXApplicationDelegate.h
//  rivenx
//
//  Created by Jean-Francois Roy on 30/08/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "Application/RXVersionComparator.h"
#import "Application/RXWelcomeWindowController.h"


@interface RXApplicationDelegate : NSObject {
#if defined(DEBUG)
    NSWindowController* debugConsoleWC;
#endif
    
    IBOutlet NSWindow* aboutBox;
    IBOutlet NSTextField* versionField;
    IBOutlet NSTextField* copyrightField;
    
    IBOutlet RXVersionComparator* versionComparator;
    
    RXWelcomeWindowController* welcomeController;
    
    BOOL canSave;
    BOOL wasFullscreen;
}

- (IBAction)orderFrontAboutWindow:(id)sender;
- (IBAction)showAcknowledgments:(id)sender;

- (IBAction)openDocument:(id)sender;
- (IBAction)saveGame:(id)sender;
- (IBAction)saveGameAs:(id)sender;

- (IBAction)toggleFullscreen:(id)sender;

- (BOOL)isGameLoaded;

@end
