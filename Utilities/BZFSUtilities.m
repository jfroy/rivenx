//
//  BZFSUtilities.m
//  rivenx
//
//  Created by Jean-Francois Roy on 05/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "Base/PHSErrorMacros.h"
#import "BZFSUtilities.h"


BOOL BZFSFileExists(NSString* path) {
	BOOL isDirectory;
	if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] == NO)
		return NO;
	if (isDirectory)
		return NO;
	return YES;	
}

BOOL BZFSFileURLExists(NSURL* url) {
	return BZFSFileExists([url path]);
}

BOOL BZFSDirectoryExists(NSString* path) {
	BOOL isDirectory;
	if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] == NO)
		return NO;
	if (!isDirectory)
		return NO;
	return YES;
}

BOOL BZFSCreateDirectory(NSString* path, NSError** error) {
	BOOL success;
	NSFileManager* fm = [NSFileManager defaultManager];
	if ([fm respondsToSelector:@selector(createDirectoryAtPath:withIntermediateDirectories:attributes:error:)])
		success = [fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:error];
	else {
		success = [fm createDirectoryAtPath:path attributes:nil];
		if (!success && error)
			*error = [NSError errorWithDomain:@"BZFSErrorDomain" code:0 userInfo:nil];
	}
	return success;
}

BOOL BZFSDirectoryURLExists(NSURL* url) {
	return BZFSDirectoryExists([url path]);
}

BOOL BZFSCreateDirectoryURL(NSURL* url, NSError** error) {
	return BZFSCreateDirectory([url path], error);
}

NSArray* BZFSContentsOfDirectory(NSString* path, NSError** error) {
	NSArray* contents;
	NSFileManager* fm = [NSFileManager defaultManager];
	if ([fm respondsToSelector:@selector(contentsOfDirectoryAtPath:error:)])
		contents = [fm contentsOfDirectoryAtPath:path error:error];
	else {
		contents = [fm directoryContentsAtPath:path];
		if (!contents && error)
			*error = [NSError errorWithDomain:@"BZFSErrorDomain" code:0 userInfo:nil];
	}
	return contents;
}

NSArray* BZFSContentsOfDirectoryURL(NSURL* url, NSError** error) {
	return BZFSContentsOfDirectory([url path], error);
}

NSDictionary* BZFSAttributesOfItemAtPath(NSString* path, NSError** error) {
	NSDictionary* attributes;
	NSFileManager* fm = [NSFileManager defaultManager];
	if ([fm respondsToSelector:@selector(attributesOfItemAtPath:error:)])
		attributes = [fm attributesOfItemAtPath:path error:error];
	else {
		attributes = [fm fileAttributesAtPath:path traverseLink:NO];
		if (!attributes && error)
			*error = [NSError errorWithDomain:@"BZFSErrorDomain" code:0 userInfo:nil];
	}
	return attributes;
}

NSDictionary* BZFSAttributesOfItemAtURL(NSURL* url, NSError** error) {
	return BZFSAttributesOfItemAtPath([url path], error);
}

BOOL BZFSRemoveItemAtURL(NSURL* url, NSError** error) {
	BOOL success;
	NSFileManager* fm = [NSFileManager defaultManager];
	if ([fm respondsToSelector:@selector(removeItemAtPath:error:)])
		success = [fm removeItemAtPath:[url path] error:error];
	else {
		success = [fm removeFileAtPath:[url path] handler:nil];
		if (!success && error)
			*error = [NSError errorWithDomain:@"BZFSErrorDomain" code:0 userInfo:nil];
	}
	return success;
}

NSFileHandle* BZFSCreateTemporaryFileInDirectory(NSURL* directory, NSString* filenameTemplate, NSURL** tempFileURL, NSError** error) {
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
