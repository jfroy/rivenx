/*
 *  MHKErrors.m
 *  MHKKit
 *
 *  Created by Jean-Francois Roy on 06/23/2005.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#import "MHKErrors.h"


NSString *const MHKErrorDomain = @"MHKErrorDomain";

@implementation MHKError

- (NSString*)localizedDescription {
    NSString* description = [[self userInfo] objectForKey:NSLocalizedDescriptionKey];
    if (description)
        return description;
    
    NSUInteger code = [self code];
    if ([[self domain] isEqualToString:MHKErrorDomain]) {
        switch (code) {
            case errFileTooLarge: return @"File is too large.";
            case errBadArchive: return @"Riven archive is invalid.";
            case errResourceNotFound: return @"A required game resource was not found.";
            case errDamagedResource: return @"A required game resource is damaged.";
            case errInvalidChannelCount: return @"Invalid number of audio channels.";
            case errInvalidFrameCount: return @"Invalid number of audio frames.";
            case errFFMPEGNotAvailable: return @"Failed to load the FFmpeg library. Music and other audio effects in the game may not play.";
            case errInvalidSoundDescriptor: return @"Invalid sound descriptor.";
            case errInvalidBitmapCompression: return @"Invalid bitmap compression.";
            case errInvalidBitmapCompressorInstruction: return @"Invalid bitmap compression instruction.";
            
            default: return [NSString stringWithFormat:@"Unknown error code (%u).", code];
        }
    }
    
    return [super localizedDescription];
}

@end
