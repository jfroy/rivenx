// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "mhk/MHKFileHandle_Internal.h"

#import "Base/RXBase.h"
#import "Base/RXErrorMacros.h"

#import "mhk/MHKArchive_Internal.h"
#import "mhk/MHKErrors.h"

@implementation MHKFileHandle {
  off_t _archiveOffset;
  off_t _ioOffset;
  int _fd;
}

- (instancetype)init {
  [self doesNotRecognizeSelector:_cmd];
  return [self initWithArchive:nil length:0 archiveOffset:0 ioOffset:0];
}

- (instancetype)initWithArchive:(MHKArchive*)archive
                         length:(off_t)length
                  archiveOffset:(off_t)archiveOffset
                       ioOffset:(off_t)ioOffset {
  self = [super init];
  if (!self) {
    return nil;
  }

  if (!archive) {
    [self release];
    return nil;
  }

  _archive = [archive retain];
  _fd = _archive->_fd;
  _length = length;
  _archiveOffset = archiveOffset;
  _ioOffset = ioOffset;

  return self;
}

- (void)dealloc {
  [_archive release];
  [super dealloc];
}

- (NSData*)readDataOfLength:(size_t)length error:(NSError**)outError {
  void* buffer = malloc(length);
  release_assert(buffer);

  ssize_t bytes_read = [self readDataOfLength:length inBuffer:buffer error:outError];
  if (bytes_read == -1) {
    free(buffer);
    return nil;
  }

  return [[[NSData alloc] initWithBytesNoCopy:buffer length:bytes_read freeWhenDone:YES] autorelease];
}

- (NSData*)readDataToEndOfFile:(NSError**)outError {
  return [self readDataOfLength:_length error:outError];
}

- (ssize_t)readDataOfLength:(size_t)length inBuffer:(void*)buffer error:(NSError**)outError {
  off_t io_offset = _ioOffset + _offsetInFile;
  off_t io_offset_end = io_offset + length;

  if (io_offset < _archiveOffset) {
    ReturnValueWithError(-1, NSPOSIXErrorDomain, EINVAL, nil, outError);
  }

  if (io_offset_end > _archiveOffset + _length) {
    io_offset_end = _archiveOffset + _length;
  }

  ssize_t io_size = io_offset_end - io_offset;
  if (io_size <= 0) {
    return 0;
  }

  ssize_t bytes_read = pread(_fd, buffer, io_size, io_offset);
  if (bytes_read < 0) {
    ReturnValueWithPOSIXError(-1, nil, outError);
  }

  _offsetInFile += bytes_read;

  return bytes_read;
}

- (ssize_t)readDataToEndOfFileInBuffer:(void*)buffer error:(NSError**)outError {
  return [self readDataOfLength:_length inBuffer:buffer error:outError];
}

- (off_t)seekToEndOfFile {
  return [self seekToFileOffset:_archiveOffset + _length - _ioOffset];
}

- (off_t)seekToFileOffset:(off_t)offset {
  if (offset < 0) {
    return -1;
  }
  _offsetInFile = offset;
  return _offsetInFile;
}

@end
