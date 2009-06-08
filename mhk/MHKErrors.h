/*
 *	MHKErrors.h
 *	MHKKit
 *
 *	Created by Jean-Francois Roy on 06/23/2005.
 *	Copyright 2005 MacStorm. All rights reserved.
 *
 */

#import <Foundation/NSString.h>


// error domains
extern NSString *const MHKErrorDomain;
extern NSString *const MHKffmpegErrorDomain;

// MHK errors
typedef enum {
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
} MHKError;
