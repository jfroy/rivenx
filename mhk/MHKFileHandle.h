// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import <Foundation/NSData.h>
#import <Foundation/NSError.h>

@class MHKArchive;

@interface MHKFileHandle : NSObject

@property (nonatomic, strong, readonly) MHKArchive* archive;
@property (nonatomic, readonly) off_t offsetInFile;
@property (nonatomic, readonly) off_t length;

- (NSData*)readDataToEndOfFile:(NSError**)outError;
- (NSData*)readDataOfLength:(size_t)length error:(NSError**)outError;

- (ssize_t)readDataOfLength:(size_t)length inBuffer:(void*)buffer error:(NSError**)outError;
- (ssize_t)readDataToEndOfFileInBuffer:(void*)buffer error:(NSError**)outError;

- (off_t)seekToEndOfFile;
- (off_t)seekToFileOffset:(off_t)offset;

@end
