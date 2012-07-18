//
//  BZFSUtilities.h
//  rivenx
//
//  Created by Jean-Francois Roy on 05/02/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"


@class NSFileHandle;

__BEGIN_DECLS

extern NSString* const BZFSErrorDomain;

BOOL BZFSFileExists(NSString* path);
BOOL BZFSFileURLExists(NSURL* url);

BOOL BZFSDirectoryExists(NSString* path);
BOOL BZFSCreateDirectory(NSString* path, NSError** error);
BOOL BZFSCreateDirectoryExtended(NSString* path, NSString* group, uint32_t permissions, NSError** error);

BOOL BZFSDirectoryURLExists(NSURL* url);
BOOL BZFSCreateDirectoryURL(NSURL* url, NSError** error);
BOOL BZFSCreateDirectoryURLExtended(NSURL* url, NSString* group, uint32_t permissions, NSError** error);

NSArray* BZFSContentsOfDirectory(NSString* path, NSError** error);
NSArray* BZFSContentsOfDirectoryURL(NSURL* url, NSError** error);

NSString* BZFSSearchDirectoryForItem(NSString* path, NSString* name, BOOL case_insensitive, NSError** error);

NSDictionary* BZFSAttributesOfItemAtPath(NSString* path, NSError** error);
NSDictionary* BZFSAttributesOfItemAtURL(NSURL* url, NSError** error);
BOOL BZFSSetAttributesOfItemAtPath(NSString* path, NSDictionary* attributes, NSError** error);

BOOL BZFSRemoveItemAtURL(NSURL* url, NSError** error);

NSFileHandle* BZFSCreateTemporaryFileInDirectory(NSURL* directory, NSString* filenameTemplate, NSURL** tempFileURL, NSError** error);

__END_DECLS
