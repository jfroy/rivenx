//
//  RXApplicationDelegate.h
//  rivenx
//
//  Created by Jean-Francois Roy on 30/08/2005.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"


@class RXVersionComparator, RXWelcomeWindowController, NSButton, NSWindowController, NSWindow, NSTextField;

@interface RXApplicationDelegate : NSObject
{
#if defined(DEBUG)
    NSWindowController* debugConsoleWC;
#endif
    
    IBOutlet NSWindow* aboutBox;
    IBOutlet NSTextField* versionField;
    IBOutlet NSTextField* copyrightField;
    IBOutlet NSButton* acknowledgmentsButton;
    
    IBOutlet RXVersionComparator* versionComparator;
    
    RXWelcomeWindowController* welcomeController;
    
    NSURL* autosaveURL;
    
    BOOL disableGameSavingAndLoading;
    BOOL missedAutosave;
    BOOL wasFullscreen;
    BOOL quicktimeGood;
}

+ (RXApplicationDelegate *)sharedApplicationDelegate;

- (IBAction)orderFrontAboutWindow:(id)sender;
- (IBAction)showAcknowledgments:(id)sender;

- (IBAction)openDocument:(id)sender;
- (IBAction)saveGame:(id)sender;
- (IBAction)saveGameAs:(id)sender;

- (BOOL)isGameLoaded;

- (BOOL)isGameLoadingAndSavingDisabled;
- (void)setDisableGameLoadingAndSaving:(BOOL)disable;

@end
