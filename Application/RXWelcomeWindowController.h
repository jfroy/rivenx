//
//  RXWelcomeWindowController.h
//  rivenx
//
//  Created by Jean-Francois Roy on 13/02/2010.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"
#import "Application/RXMediaInstaller.h"

#import <AppKit/NSWindowController.h>
#import <AppKit/NSSavePanel.h>


@class NSPanel, NSTextField, NSProgressIndicator, NSButton, NSAlert;

@interface RXWelcomeWindowController : NSWindowController <RXMediaInstallerMediaProviderProtocol, NSOpenSavePanelDelegate>
{
    IBOutlet NSPanel* _installingSheet;
    IBOutlet NSTextField* _installingTitleField;
    IBOutlet NSTextField* _installingStatusField;
    IBOutlet NSProgressIndicator* _installingProgress;
    IBOutlet NSButton* _cancelInstallButton;
    
    NSThread* scanningThread;
    FSEventStreamRef _downloadsFSEventStream;
    NSString* _downloadsFolderPath;
    BOOL _gogInstallerFoundInDownloadsFolder;
    
    RXInstaller* installer;
    NSModalSession installerSession;
    NSString* waitedOnDisc;
    
    NSAlert* _gogBuyAlert;
    BOOL alertOrPanelCurrentlyActive;
}

- (IBAction)buyRiven:(id)sender;
- (IBAction)installFromFolder:(id)sender;

- (IBAction)cancelInstallation:(id)sender;

@end
