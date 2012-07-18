//
//  RXMediaInstaller.h
//  rivenx
//
//  Created by Jean-Francois Roy on 08/02/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "RXInstaller.h"


@protocol RXMediaInstallerMediaProviderProtocol <NSObject>
- (BOOL)waitForDisc:(NSString*)disc_name ejectingDisc:(NSString*)path error:(NSError**)error;
@end

@interface RXMediaInstaller : RXInstaller
{
@private
    uint64_t totalBytesToCopy;
    uint64_t totalBytesCopied;
    
    NSMutableArray* discsToProcess;
    NSString* currentDisc;
    
    id <RXMediaInstallerMediaProviderProtocol> mediaProvider;
    
    NSString* dataPath;
    NSArray* dataArchives;
    
    NSString* assetsPath;
    NSArray* assetsArchives;
    
    NSString* allPath;
    NSArray* allArchives;
    
    NSString* extrasPath;
}

- (id)initWithMountPaths:(NSDictionary*)mount_paths mediaProvider:(id <RXMediaInstallerMediaProviderProtocol>)mp;

@end
