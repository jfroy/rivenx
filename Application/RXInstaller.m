//
//  RXInstaller.m
//  rivenx
//
//  Created by Jean-François Roy on 30/12/2011.
//  Copyright (c) 2012 MacStorm. All rights reserved.
//

#import "RXInstaller.h"

#import <Foundation/NSBundle.h>


@implementation RXInstaller

- (id)init
{
    self = [super init];
    if (!self)
        return nil;
    
    progress = -1.0;
    stage = [NSLocalizedStringFromTable(@"INSTALLER_PREPARING", @"Installer", NULL) retain];
    
    return self;
}

- (void)dealloc
{
    [stage release];
    [destination release];
    
    [super dealloc];
}

- (BOOL)runWithModalSession:(NSModalSession)session error:(NSError**)error
{
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

- (void)updatePathsWithMountPaths:(NSDictionary*)mount_paths
{
    [self doesNotRecognizeSelector:_cmd];
}

@end
