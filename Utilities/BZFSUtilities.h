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

enum {
    kBZFSErrUnknownError = 1,
};

extern NSString* const BZFSErrorDomain;

extern BOOL BZFSFileExists(NSString* path);
extern BOOL BZFSFileURLExists(NSURL* url);

extern BOOL BZFSDirectoryExists(NSString* path);
extern BOOL BZFSCreateDirectory(NSString* path, NSError** error);
BOOL BZFSCreateDirectoryExtended(NSString* path, NSString* group, uint32_t permissions, NSError** error);

extern BOOL BZFSDirectoryURLExists(NSURL* url);
extern BOOL BZFSCreateDirectoryURL(NSURL* url, NSError** error);

extern NSArray* BZFSContentsOfDirectory(NSString* path, NSError** error);
extern NSArray* BZFSContentsOfDirectoryURL(NSURL* url, NSError** error);

extern NSString* BZFSSearchDirectoryForItem(NSString* path, NSString* name, BOOL case_insensitive, NSError** error);

extern NSDictionary* BZFSAttributesOfItemAtPath(NSString* path, NSError** error);
extern NSDictionary* BZFSAttributesOfItemAtURL(NSURL* url, NSError** error);
extern BOOL BZFSSetAttributesOfItemAtPath(NSString* path, NSDictionary* attributes, NSError** error);

extern BOOL BZFSRemoveItemAtURL(NSURL* url, NSError** error);

extern NSFileHandle* BZFSCreateTemporaryFileInDirectory(NSURL* directory, NSString* filenameTemplate, NSURL** tempFileURL, NSError** error);

__END_DECLS
