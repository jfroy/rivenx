//
//  RXApplicationDelegate.h
//  rivenx
//
//  Created by Jean-Francois Roy on 30/08/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "RXVersionComparator.h"


@interface RXApplicationDelegate : NSObject {
#if defined(DEBUG)
    NSWindowController* _debugConsoleWC;
//  NSWindowController* _engineVariableEditorWC;
//  NSWindowController* _gameVariableEditorWC;
//  NSWindowController* _card_inspector_controller;
#endif
    
    IBOutlet NSWindow* _aboutBox;
    IBOutlet NSWindow* _preferences;
    IBOutlet NSTextField* _versionField;
    IBOutlet NSTextField* _copyrightField;
    
    IBOutlet RXVersionComparator* versionComparator;
    
    BOOL _saveFlag;
    BOOL _canSave;
    BOOL _fullscreen;
}

- (IBAction)orderFrontAboutWindow:(id)sender;
- (IBAction)showAcknowledgments:(id)sender;

- (IBAction)showPreferences:(id)sender;

- (IBAction)openDocument:(id)sender;
- (IBAction)saveGame:(id)sender;
- (IBAction)saveGameAs:(id)sender;

- (BOOL)isSavingEnabled;
- (void)setSavingEnabled:(BOOL)flag;

- (IBAction)toggleFullscreen:(id)sender;
- (IBAction)toggleStretchToFit:(id)sender;
- (BOOL)isFullscreen;

@end
