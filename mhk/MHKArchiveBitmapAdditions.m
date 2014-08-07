// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "Base/RXBase.h"
#import "Base/RXErrorMacros.h"

#import "mhk/mohawk_bitmap.h"

#import "mhk/MHKArchive_Internal.h"
#import "mhk/MHKArchiveMediaInterface.h"
#import "mhk/MHKErrors.h"

@implementation MHKBitmapDescriptor {
 @package
  int32_t _width;
  int32_t _height;
}
@end

@implementation MHKArchive (MHKArchiveBitmapAdditions)

- (MHKBitmapDescriptor*)bitmapDescriptorWithID:(uint16_t)bitmapID error:(NSError**)outError {
  // get a resource descriptor
  MHKResourceDescriptor* rdesc = [self resourceDescriptorWithResourceType:@"tBMP" ID:bitmapID];
  if (!rdesc) {
    ReturnValueWithError(nil, MHKErrorDomain, errResourceNotFound, nil, outError);
  }

  // read the bitmap header
  MHK_BITMAP_header bitmap_header;
  ssize_t bytes_read = pread(_fd, &bitmap_header, sizeof(MHK_BITMAP_header), rdesc.offset);
  if (bytes_read < 0) {
    ReturnValueWithError(nil, MHKErrorDomain, errDamagedResource, nil, outError);
  }
  MHK_BITMAP_header_fton(&bitmap_header);

  // return a bitmap descriptor
  MHKBitmapDescriptor* bdesc = [MHKBitmapDescriptor new];
  bdesc->_width = bitmap_header.width;
  bdesc->_height = bitmap_header.height;
  return [bdesc autorelease];
}

- (BOOL)loadBitmapWithID:(uint16_t)bitmapID bgraBuffer:(void*)bgraBuffer error:(NSError**)outError {
  // get a resource descriptor
  MHKResourceDescriptor* rdesc = [self resourceDescriptorWithResourceType:@"tBMP" ID:bitmapID];
  if (!rdesc) {
    ReturnValueWithError(NO, MHKErrorDomain, errResourceNotFound, nil, outError);
  }

  off_t offset = rdesc.offset;

  // read the bitmap header
  MHK_BITMAP_header bitmap_header;
  ssize_t bytes_read = pread(_fd, &bitmap_header, sizeof(MHK_BITMAP_header), offset);
  if (bytes_read < 0) {
    ReturnValueWithError(NO, MHKErrorDomain, errDamagedResource, nil, outError);
  }
  MHK_BITMAP_header_fton(&bitmap_header);

  if (bitmap_header.truecolor_flag == 4) {
    return read_raw_bgr_pixels(_fd, offset + bytes_read, &bitmap_header, bgraBuffer);
  }

  // move the offset past the header and skip 2 shorts
  offset += bytes_read + 4;

  // process the pixels
  if (bitmap_header.compression_flag == MHK_BITMAP_RAW) {
    return read_raw_indexed_pixels(_fd, offset, &bitmap_header, bgraBuffer);
  } else if (bitmap_header.compression_flag == MHK_BITMAP_COMPRESSED) {
    return read_compressed_indexed_pixels(_fd, offset, &bitmap_header, bgraBuffer);
  } else {
    ReturnValueWithError(NO, MHKErrorDomain, errInvalidBitmapCompression, nil, outError);
  }
}

@end
