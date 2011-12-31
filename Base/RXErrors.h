//
//  RXErrors.h
//  rivenx
//

#if !defined(RX_ERRORS_H)
#define RX_ERRORS_H

#import "Base/RXBase.h"


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
    kRXErrFailedToGetFilesystemInformation,
    kRXErrUnusableInstallMedia,
    kRXErrUnusableInstallFolder,
    kRXErrInstallerGOGSetupUnpackFailed,
};

#if defined(__OBJC__)

#import <Foundation/NSError.h>

extern NSString* const RXErrorDomain;

@interface RXError : NSError
@end

#endif // __OBJC__

__END_DECLS

#endif // RX_ERRORS_H
