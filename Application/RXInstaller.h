//
//  RXEditionInstaller.h
//  rivenx
//
//  Created by Jean-Francois Roy on 08/02/2008.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"
#import <AppKit/NSApplication.h>


@protocol RXInstallerMediaProviderProtocol <NSObject>
- (BOOL)waitForDisc:(NSString*)disc_name ejectingDisc:(NSString*)path error:(NSError**)error;
@end

@interface RXInstaller : NSObject
{
    double progress;
    CFTimeInterval remainingTime;
    NSString* item;
    NSString* stage;
    
@private
    uint64_t totalBytesToCopy;
    uint64_t totalBytesCopied;
    
    NSMutableArray* discsToProcess;
    NSString* currentDisc;
    NSString* destination;
    
    NSModalSession modalSession;
    id <RXInstallerMediaProviderProtocol> mediaProvider;
    
    NSString* dataPath;
    NSArray* dataArchives;
    
    NSString* assetsPath;
    NSArray* assetsArchives;
    
    NSString* allPath;
    NSArray* allArchives;
    
    NSString* extrasPath;
    
    BOOL didRun;
}

- (id)initWithMountPaths:(NSDictionary*)mount_paths mediaProvider:(id <RXInstallerMediaProviderProtocol>)mp;

- (BOOL)runWithModalSession:(NSModalSession)session error:(NSError**)error;
- (void)updatePathsWithMountPaths:(NSDictionary*)mount_paths;

@end
