//
//  RXEditionManagerWindowController.h
//  rivenx
//
//  Created by Jean-Francois Roy on 02/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "RXEdition.h"


@interface RXEditionManagerWindowController : NSWindowController {
    IBOutlet NSArrayController* _editionsArrayController;
    
    IBOutlet NSTableView* _editionsTableView;
    NSSize _thumbnailSize;
    
    IBOutlet NSPanel* _installingSheet;
    IBOutlet NSTextField* _installingTitleField;
    IBOutlet NSTextField* _installingStatusField;
    IBOutlet NSProgressIndicator* _installingProgress;
    
    NSModalSession _installerSession;
    
    RXEdition* _pickedEdition;
}

- (IBAction)choose:(id)sender;
- (IBAction)install:(id)sender;

- (IBAction)cancelInstallation:(id)sender;

@end
