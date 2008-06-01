//
//  BZFSUtilities.h
//  rivenx
//
//  Created by Jean-Francois Roy on 05/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sys/cdefs.h>

__BEGIN_DECLS

BOOL BZFSFileExists(NSString* path);

BOOL BZFSDirectoryExists(NSString* path);
BOOL BZFSCreateDirectory(NSString* path, NSError** error);

NSArray* BZFSContentsOfDirectory(NSString* path, NSError** error);

NSDictionary* BZFSAttributesOfItemAtPath(NSString* path, NSError** error);

__END_DECLS
