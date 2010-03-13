//
//  RXErrors.h
//  rivenx
//
//  Created by Jean-Francois Roy on 7/27/07.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#if !defined(RXERRORS_H)
#define RXERRORS_H

#import <sys/cdefs.h>

__BEGIN_DECLS

enum {
    kRXErrSavedGameCantBeLoaded,
    kRXErrQuickTimeTooOld,
    
    kRXErrArchivesNotFound,
    kRXErrFailedToInitializeStack,
    
    kRXErrFailedToGetDisplayID,
    kRXErrNoAcceleratorService,
    kRXErrFailedToGetAcceleratorPerfStats,
    kRXErrFailedToFindFreeVRAMInformation,
    kRXErrFailedToCreatePixelFormat,
    
    kRXErrInstallerAlreadyRan,
    kRXErrInstallerMissingArchivesOnMedia,
    kRXErrInstallerCancelled,
    kRXErrInstallerMissingArchivesAfterInstall,
};

#if defined(__OBJC__)

#import "Base/PHSErrorMacros.h"

extern NSString* const RXErrorDomain;

@interface RXError : NSError
@end

#endif

__END_DECLS

#endif // RXERRORS_H
