//
//  RXApplicationDelegate.h
//  rivenx
//
//  Created by Jean-Francois Roy on 30/08/2005.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@class SUUpdater;
@class RXVersionComparator;
@class RXWelcomeWindowController;

@interface RXApplicationDelegate : NSObject {
#if defined(DEBUG)
    NSWindowController* debugConsoleWC;
#endif
    
    IBOutlet NSWindow* aboutBox;
    IBOutlet NSTextField* versionField;
    IBOutlet NSTextField* copyrightField;
    
    IBOutlet SUUpdater* updater;
    IBOutlet RXVersionComparator* versionComparator;
    
    RXWelcomeWindowController* welcomeController;
    
    NSString* savedGamesDirectory;
    NSURL* autosaveURL;
    
    BOOL disableGameSavingAndLoading;
    BOOL missedAutosave;
    BOOL wasFullscreen;
    BOOL quicktimeGood;
}

- (IBAction)orderFrontAboutWindow:(id)sender;
- (IBAction)showAcknowledgments:(id)sender;

- (IBAction)openDocument:(id)sender;
- (IBAction)saveGame:(id)sender;
- (IBAction)saveGameAs:(id)sender;

- (IBAction)toggleFullscreen:(id)sender;

- (BOOL)isGameLoaded;

- (BOOL)isGameLoadingAndSavingDisabled;
- (void)setDisableGameLoadingAndSaving:(BOOL)disable;

@end
