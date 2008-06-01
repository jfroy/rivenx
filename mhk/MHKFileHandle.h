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
	SInt16 __forkRef;
	MHKArchive *__owner;
	
	SInt64 __offset;
	UInt32 __position;
	UInt32 __length;
}

- (UInt32)readDataOfLength:(UInt32)length inBuffer:(void *)buffer error:(NSError **)errorPtr;
- (void)readDataToEndOfFileInBuffer:(void *)buffer error:(NSError **)errorPtr;

- (SInt64)offsetInFile;
- (SInt64)seekToEndOfFile;
- (SInt64)seekToFileOffset:(SInt64)offset;

- (SInt64)length;

@end
