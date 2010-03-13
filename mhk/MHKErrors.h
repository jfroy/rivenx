/*
 *  MHKErrors.h
 *  MHKKit
 *
 *  Created by Jean-Francois Roy on 06/23/2005.
 *  Copyright 2005-2010 MacStorm. All rights reserved.
 *
 */

#import <Foundation/Foundation.h>

#import "Base/PHSErrorMacros.h"


// error domains
extern NSString *const MHKErrorDomain;

// MHK errors
enum {
    errFileTooLarge = 1, 
    errBadArchive, 
    errResourceNotFound,
    errDamagedResource, 
    errInvalidChannelCount, 
    errInvalidFrameCount, 
    errFFMPEGNotAvailable, 
    errInvalidSoundDescriptor, 
    errInvalidBitmapCompression, 
    errInvalidBitmapCompressorInstruction
};

@interface MHKError : NSError
@end
