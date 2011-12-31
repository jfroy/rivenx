//
//  RXErrors.m
//  rivenx
//
//  Created by Jean-Francois Roy on 7/27/07.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "Base/RXErrors.h"


NSString* const RXErrorDomain = @"RXErrorDomain";

@implementation RXError

- (NSString*)localizedDescription {
    NSString* description = [[self userInfo] objectForKey:NSLocalizedDescriptionKey];
    if (description)
        return description;
    
    NSUInteger code = [self code];
    if ([[self domain] isEqualToString:RXErrorDomain]) {
        switch (code) {
            case kRXErrSavedGameCantBeLoaded: return @"Save game cannot be loaded.";
            case kRXErrQuickTimeTooOld: return @"QuickTime is too old.";
            
            case kRXErrArchivesNotFound: return @"Failed to find required Riven data files.";
            case kRXErrFailedToInitializeStack: return @"Riven X was unable to load a segment of Riven.";
            
            case kRXErrFailedToGetDisplayID: return @"Failed to get display ID.";
            case kRXErrNoAcceleratorService: return @"No graphics accelerator service.";
            case kRXErrFailedToGetAcceleratorPerfStats: return @"Failed to get graphics accelerator performance statistics.";
            case kRXErrFailedToFindFreeVRAMInformation: return @"Failed to determine the amount of free VRAM.";
            case kRXErrFailedToCreatePixelFormat: return @"Failed to creare a pixel format.";
            
            case kRXErrInstallerAlreadyRan: return @"Installer already ran.";
            case kRXErrInstallerMissingArchivesOnMedia: return @"Media is missing some Riven data files.";
            case kRXErrInstallerCancelled: return @"Installer was cancelled.";
            case kRXErrInstallerMissingArchivesAfterInstall: return @"Riven data files are missing after installation.";
            case kRXErrFailedToGetFilesystemInformation: return @"Riven X failed to obtain filesystem information for the selected media.";
            case kRXErrUnusableInstallMedia: return @"Riven X cannot install from the selected disc because it does not appear to be a Riven disc.";
            case kRXErrUnusableInstallFolder: return @"Riven X cannot install from the selected folder because it does not appear to contain Riven.";
            case kRXErrInstallerGOGSetupUnpackFailed: return @"Riven X failed to unpack the GOG.com Riven installer.";
            
            default: return [NSString stringWithFormat:@"Unknown error code (%lu).", code];
        }
    }
    
    return [super localizedDescription];
}

@end
