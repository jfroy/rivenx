//
//  MHKQTPlayerController.h
//  MHKKit
//
//  Created by Jean-Francois Roy on 09/04/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <QTKit/QTKit.h>
#import <MHKKit/MHKKit.h>


@interface MHKQTPlayerController : NSObject {
    IBOutlet QTMovieView *qtView;
    IBOutlet NSDrawer *mediaListDrawer;
    IBOutlet NSTableView* movieTableView;
    
    MHKArchive *archive;
}

@end
