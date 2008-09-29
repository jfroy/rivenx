//
//	MHKFileHandle.m
//	MHKKit
//
//	Created by Jean-Francois Roy on 07/04/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import "MHKFileHandle.h"
#import "MHKArchive.h"
#import "PHSErrorMacros.h"

@implementation MHKFileHandle

- (id)init {
	[super init];
	[self release];
	return nil;
}

- (id)_initWithArchive:(MHKArchive *)archive fork:(SInt16)forkRef descriptor:(NSDictionary *)desc {
	self = [super init];
	if (!self) return nil;
	
	// weak reference, MHKArchive ensures it won't go away until all its files have dealloc-ed
	__owner = archive;
	__forkRef = forkRef;
	
	__offset = [[desc objectForKey:@"Offset"] longLongValue];
	__position = 0;
	__length = [[desc objectForKey:@"Length"] unsignedLongValue];
	
	return self;
}

- (id)_initWithArchive:(MHKArchive *)archive fork:(SInt16)forkRef soundDescriptor:(NSDictionary *)sdesc {
	self = [super init];
	if (!self) return nil;
	
	// weak reference, MHKArchive ensures it won't go away until all its files have dealloc-ed
	__owner = archive;
	__forkRef = forkRef;
	
	__offset = [[sdesc objectForKey:@"Samples Absolute Offset"] longLongValue];
	__position = 0;
	__length = [[sdesc objectForKey:@"Samples Length"] unsignedLongValue];
	
	return self;
}

- (void)dealloc {
	[__owner performSelector:@selector(_fileDidDealloc)];
	[super dealloc];
}

- (UInt32)readDataOfLength:(UInt32)length inBuffer:(void *)buffer error:(NSError **)errorPtr {
	// is the request valid?
	if (__position == __length)
		ReturnValueWithError(0, NSOSStatusErrorDomain, eofErr, nil, errorPtr)
	if (__length - __position < length)
		length = __length - __position;
	
	// read the data from the file
	UInt32 bytes_read = 0;
	OSStatus err = FSReadFork(__forkRef, fsFromStart | forceReadMask, __offset + __position, length, buffer, &bytes_read);
	if (err && err != eofErr)
		ReturnValueWithError(0, NSOSStatusErrorDomain, err, nil, errorPtr)
	
	// update the position
	__position += bytes_read;
	
	if (err)
		ReturnValueWithError(bytes_read, NSOSStatusErrorDomain, err, nil, errorPtr)
	return bytes_read;
}

- (void)readDataToEndOfFileInBuffer:(void *)buffer error:(NSError **)errorPtr {
	[self readDataOfLength:__length inBuffer:buffer error:errorPtr];
}

- (SInt64)offsetInFile {
	return __position;
}

- (SInt64)seekToEndOfFile {
	__position = __length;
	return __position;
}

- (SInt64)seekToFileOffset:(SInt64)offset {
	if (offset > __length)
		return -1;
	
	// Explicit cast OK here, MHK file sizes are 32 bit
	__position = (UInt32)offset;
	return __position;
}

- (SInt64)length {
	return (SInt64)__length;
}

@end
