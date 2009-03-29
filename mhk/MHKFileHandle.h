//
//	MHKFileHandle.h
//	MHKKit
//
//	Created by Jean-Francois Roy on 07/04/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MHKArchive;


@interface MHKFileHandle : NSObject {
	int16_t __forkRef;
	MHKArchive* __owner;
	
	off_t __offset;
	uint32_t __position;
	uint32_t __length;
}

- (MHKArchive*)archive;

- (NSData*)readDataOfLength:(size_t)length error:(NSError**)error;
- (NSData*)readDataToEndOfFile:(NSError**)error;

- (ssize_t)readDataOfLength:(size_t)length inBuffer:(void*)buffer error:(NSError**)error;
- (ssize_t)readDataToEndOfFileInBuffer:(void*)buffer error:(NSError**)error;

- (off_t)offsetInFile;
- (off_t)seekToEndOfFile;
- (off_t)seekToFileOffset:(SInt64)offset;

- (off_t)length;

@end
