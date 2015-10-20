// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "mhk/MHKErrors.h"

NSString* const MHKErrorDomain = @"MHKErrorDomain";

@implementation MHKError

- (NSString*)localizedDescription {
  NSString* description = [[self userInfo] objectForKey:NSLocalizedDescriptionKey];
  if (description) {
    return description;
  }

  NSUInteger code = [self code];
  if ([[self domain] isEqualToString:MHKErrorDomain]) {
    switch (code) {
      case errBadArchive:
        return @"Riven archive is invalid.";
      case errResourceNotFound:
        return @"A required game resource was not found.";
      case errDamagedResource:
        return @"A required game resource is damaged.";
      case errInvalidChannelCount:
        return @"Invalid number of audio channels.";
      case errInvalidFrameCount:
        return @"Invalid number of audio frames.";
      case errFFmpegNotAvailable:
        return @"Failed to load FFmpeg.";
      case errFFmpegError:
        return @"FFmpeg error.";
      case errInvalidSoundDescriptor:
        return @"Invalid sound descriptor.";
      case errInvalidBitmapCompression:
        return @"Invalid bitmap compression.";
      case errInvalidBitmapCompressorInstruction:
        return @"Invalid bitmap compression instruction.";
      default:
        return [NSString stringWithFormat:@"Unknown error code (%lu).", (unsigned long)code];
    }
  }
  return [super localizedDescription];
}

@end
