//
//  RXInstaller.h
//  rivenx
//
//  Created by Jean-François Roy on 30/12/2011.
//  Copyright (c) 2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"
#import <AppKit/NSApplication.h>


@interface RXInstaller : NSObject
{
    double progress;
    NSString* stage;
    
    NSModalSession modalSession;
    NSString* destination;
    BOOL didRun;
}

- (BOOL)runWithModalSession:(NSModalSession)session error:(NSError**)error;
- (void)updatePathsWithMountPaths:(NSDictionary*)mount_paths;

@end
