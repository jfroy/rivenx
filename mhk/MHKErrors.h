// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#import <sys/cdefs.h>

__BEGIN_DECLS

// MHK errors
enum {
  errBadArchive = 1,
  errResourceNotFound,
  errDamagedResource,
  errInvalidChannelCount,
  errInvalidFrameCount,
  errLibavNotAvailable,
  errLibavError,
  errInvalidSoundDescriptor,
  errInvalidBitmapCompression,
  errInvalidBitmapCompressorInstruction
};

#if defined(__OBJC__)

#import <Foundation/NSString.h>
#import <Foundation/NSError.h>

extern NSString* const MHKErrorDomain;

@interface MHKError : NSError
@end

#endif  // __OBJC__

__END_DECLS
