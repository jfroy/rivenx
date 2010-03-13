//
//  RXExceptions.h
//  rivenx
//
//  Created by Jean-Francois Roy on 7/27/07.
//  Copyright 2007 MacStorm. All rights reserved.
//

#if !defined(RXERRORS_H)
#define RXERRORS_H

#import <sys/cdefs.h>

__BEGIN_DECLS

#import <Cocoa/Cocoa.h>
#import "PHSErrorMacros.h"


enum {
    kRXErrSavedGameCantBeLoaded,
    kRXErrQuickTimeTooOld,
    
    kRXErrArchivesNotFound,
    
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

extern NSString* const RXErrorDomain;
extern NSString* const RXIOKitErrorDomain;
extern NSString* const RXCGLErrorDomain;
extern NSString* const RXCGErrorDomain;

extern NSException* RXArchiveManagerArchiveNotFoundExceptionWithArchiveName(NSString* name);

__END_DECLS

#endif // RXERRORS_H
