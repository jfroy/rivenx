//
//  MHKQTPlayerController.h
//  MHKKit
//
//  Created by Jean-Francois Roy on 09/04/2005.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"
#import <QTKit/QTKit.h>
#import <MHKKit/MHKKit.h>


@interface MHKQTPlayerController : NSObject {
    IBOutlet QTMovieView *qtView;
    IBOutlet NSDrawer *mediaListDrawer;
    IBOutlet NSTableView* movieTableView;
    
    IBOutlet NSTextField* timeValueField;
    IBOutlet NSTextField* timeBaseField;
    
    MHKArchive *archive;
}

- (IBAction)setCurrentTime:(id)sender;
- (IBAction)getCurrentTime:(id)sender;

@end
