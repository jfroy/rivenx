/*
 *  MHKErrors.h
 *  MHKKit
 *
 *  Created by Jean-Francois Roy on 06/23/2005.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#if !defined(MHK_ERRORS_H)
#define MHK_ERRORS_H

#import <sys/cdefs.h>


__BEGIN_DECLS

// MHK errors
enum {
    errFileTooLarge = 1, 
    errBadArchive, 
    errResourceNotFound,
    errDamagedResource, 
    errInvalidChannelCount, 
    errInvalidFrameCount, 
    errLibavNotAvailable, 
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

#endif // __OBJC__

__END_DECLS

#endif // MHK_ERRORS_H
