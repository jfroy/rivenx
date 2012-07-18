//
//  BZFSUtilities.m
//  rivenx
//
//  Created by Jean-Francois Roy on 05/02/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "BZFSUtilities.h"
#import "Base/RXErrorMacros.h"

#import <Foundation/NSBundle.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSFileHandle.h>


NSString* const BZFSErrorDomain = @"BZFSErrorDomain";

BOOL BZFSFileExists(NSString* path)
{
    BOOL isDirectory;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] == NO)
        return NO;
    if (isDirectory)
        return NO;
    return YES; 
}

BOOL BZFSFileURLExists(NSURL* url)
{
    return BZFSFileExists([url path]);
}

BOOL BZFSDirectoryExists(NSString* path)
{
    BOOL isDirectory;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] == NO)
        return NO;
    if (!isDirectory)
        return NO;
    return YES;
}

BOOL BZFSCreateDirectoryExtended(NSString* path, NSString* group, uint32_t permissions, NSError** error)
{
    NSFileManager* fm = [NSFileManager defaultManager];
    
    NSMutableDictionary* attributes = [NSMutableDictionary dictionary];
    if (permissions)
        [attributes setObject:[NSNumber numberWithUnsignedInt:permissions] forKey:NSFilePosixPermissions];
    if (group)
        [attributes setObject:group forKey:NSFileGroupOwnerAccountName];
    
    return [fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:attributes error:error];
}

BOOL BZFSCreateDirectory(NSString* path, NSError** error)
{
    return BZFSCreateDirectoryExtended(path, nil, 0, error);
}

BOOL BZFSDirectoryURLExists(NSURL* url)
{
    return BZFSDirectoryExists([url path]);
}

BOOL BZFSCreateDirectoryURL(NSURL* url, NSError** error)
{
    return BZFSCreateDirectory([url path], error);
}

BOOL BZFSCreateDirectoryURLExtended(NSURL* url, NSString* group, uint32_t permissions, NSError** error)
{
    return BZFSCreateDirectoryExtended([url path], group, permissions, error);
}

NSArray* BZFSContentsOfDirectory(NSString* path, NSError** error)
{
    NSFileManager* fm = [NSFileManager defaultManager];
    return [fm contentsOfDirectoryAtPath:path error:error];
}

NSArray* BZFSContentsOfDirectoryURL(NSURL* url, NSError** error)
{
    return BZFSContentsOfDirectory([url path], error);
}

NSString* BZFSSearchDirectoryForItem(NSString* path, NSString* name, BOOL case_insensitive, NSError** error)
{
    NSArray* content = BZFSContentsOfDirectory(path, error);
    if (!content)
        return NO;
    
    NSEnumerator* enumerator = [content objectEnumerator];
    NSString* item;
    while ((item = [enumerator nextObject]))
    {
        if (case_insensitive)
        {
            if ([item caseInsensitiveCompare:name] == NSOrderedSame)
                return [path stringByAppendingPathComponent:item];
        }
        else
        {
            if ([item compare:name] == NSOrderedSame)
                return [path stringByAppendingPathComponent:item];
        }
    }
    
    return nil;
}

NSDictionary* BZFSAttributesOfItemAtPath(NSString* path, NSError** error)
{
    NSFileManager* fm = [NSFileManager defaultManager];
    return [fm attributesOfItemAtPath:path error:error];
}

NSDictionary* BZFSAttributesOfItemAtURL(NSURL* url, NSError** error)
{
    return BZFSAttributesOfItemAtPath([url path], error);
}

BOOL BZFSSetAttributesOfItemAtPath(NSString* path, NSDictionary* attributes, NSError** error)
{
    NSFileManager* fm = [NSFileManager defaultManager];
    return [fm setAttributes:attributes ofItemAtPath:path error:error];
}

BOOL BZFSRemoveItemAtURL(NSURL* url, NSError** error)
{
    NSFileManager* fm = [NSFileManager defaultManager];
    return [fm removeItemAtURL:url error:error];
}

NSFileHandle* BZFSCreateTemporaryFileInDirectory(NSURL* directory, NSString* filenameTemplate, NSURL** tempFileURL, NSError** error)
{
    char* t = malloc(PATH_MAX + 1);
    if (!t)
        ReturnValueWithPOSIXError(nil, nil, error);
    
    // if not explicit parent directory was provided, use the temp directory
    NSString* parentPath;
    if (!directory)
        parentPath = NSTemporaryDirectory();
    else
        parentPath = [directory path];
    
    // if not explicit template was provided, make one up based on the bundle identifier
    if (!filenameTemplate)
        filenameTemplate = [NSString stringWithFormat:@"%@-XXXXXXXX", [[NSBundle mainBundle] bundleIdentifier]];
    
    // make up the final temp file template and convert it to the suitable C string
    [[parentPath stringByAppendingPathComponent:filenameTemplate] getFileSystemRepresentation:t maxLength:PATH_MAX + 1];
    
    // make the temp file and open it atomically
    int fd = mkstemp(t);
    if (fd == -1) {
        free(t);
        ReturnValueWithPOSIXError(nil, nil, error);
    }
    
    // return the final URL if requested
    if (tempFileURL)
        *tempFileURL = [(NSURL*)CFURLCreateFromFileSystemRepresentation(NULL, (uint8_t*)t, strlen(t), false) autorelease];
    
    // cleanup and return the descriptor wrapped in a NSFileHandle
    free(t);
    return [[[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES] autorelease];
}
