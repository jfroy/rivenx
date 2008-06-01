//
//  BZFSUtilities.m
//  rivenx
//
//  Created by Jean-Francois Roy on 05/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "BZFSUtilities.h"


BOOL BZFSFileExists(NSString* path) {
	BOOL isDirectory;
	if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] == NO) return NO;
	if (isDirectory) return NO;
	return YES;	
}

BOOL BZFSDirectoryExists(NSString* path) {
	BOOL isDirectory;
	if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] == NO) return NO;
	if (!isDirectory) return NO;
	return YES;
}

BOOL BZFSCreateDirectory(NSString* path, NSError** error) {
	BOOL success;
	NSFileManager* fm = [NSFileManager defaultManager];
#if defined(MAC_OS_X_VERSION_10_5)
	if ([fm respondsToSelector:@selector(createDirectoryAtPath:withIntermediateDirectories:attributes:error:)]) success = [fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:error];
	else {
		success = [fm createDirectoryAtPath:path attributes:nil];
#else
	{
		success = [fm createDirectoryAtPath:path attributes:nil];
#endif
		if (!success && error) *error = [NSError errorWithDomain:@"BZFSErrorDomain" code:0 userInfo:nil];
	}
	return success;
}

NSArray* BZFSContentsOfDirectory(NSString* path, NSError** error) {
	NSArray* contents;
	NSFileManager* fm = [NSFileManager defaultManager];
#if defined(MAC_OS_X_VERSION_10_5)
	if ([fm respondsToSelector:@selector(contentsOfDirectoryAtPath:error:)]) contents = [fm contentsOfDirectoryAtPath:path error:error];
	else {
		contents = [fm directoryContentsAtPath:path];
#else
	{
		contents = [fm directoryContentsAtPath:path];
#endif
		if (!contents && error) *error = [NSError errorWithDomain:@"BZFSErrorDomain" code:0 userInfo:nil];
	}
	return contents;
}

NSDictionary* BZFSAttributesOfItemAtPath(NSString* path, NSError** error) {
	NSDictionary* attributes;
	NSFileManager* fm = [NSFileManager defaultManager];
#if defined(MAC_OS_X_VERSION_10_5)
	if ([fm respondsToSelector:@selector(attributesOfItemAtPath:error:)]) attributes = [fm attributesOfItemAtPath:path error:error];
	else {
		attributes = [fm fileAttributesAtPath:path traverseLink:NO];
#else
	{
		attributes = [fm fileAttributesAtPath:path traverseLink:NO];
#endif
		if (!attributes && error) *error = [NSError errorWithDomain:@"BZFSErrorDomain" code:0 userInfo:nil];
	}
	return attributes;
}
