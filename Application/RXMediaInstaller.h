// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "RXInstaller.h"

@protocol RXMediaInstallerMediaProviderProtocol <NSObject>
- (void)waitForDisc:(NSString*)disc_name
       ejectingDisc:(NSString*)path
       continuation:(void (^)(NSDictionary* mount_paths))continuation;
@end

@interface RXMediaInstaller : NSObject <RXInstaller>

- (instancetype)initWithMountPaths:(NSDictionary*)mount_paths
                     mediaProvider:(id<RXMediaInstallerMediaProviderProtocol>)mediaProvider;

@end
