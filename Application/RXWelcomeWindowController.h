//
//  RXWelcomeWindowController.h
//  rivenx
//
//  Created by Jean-Francois Roy on 13/02/2010.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "Application/RXInstaller.h"


@interface RXWelcomeWindowController : NSWindowController <RXInstallerMediaProviderProtocol> {
    IBOutlet NSPanel* _installingSheet;
    IBOutlet NSTextField* _installingTitleField;
    IBOutlet NSTextField* _installingStatusField;
    IBOutlet NSProgressIndicator* _installingProgress;
    IBOutlet NSButton* _cancelInstallButton;
    
    NSThread* scanningThread;
    
    RXInstaller* installer;
    NSModalSession installerSession;
    NSString* waitedOnDisc;
    
    NSAlert* checkingMediaAlert;
    BOOL alertOrPanelCurrentlyActive;
}

- (IBAction)buyRiven:(id)sender;
- (IBAction)installFromFolder:(id)sender;

- (IBAction)cancelInstallation:(id)sender;

@end
