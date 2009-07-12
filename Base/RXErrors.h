//
//  RXExceptions.h
//  rivenx
//
//  Created by Jean-Francois Roy on 7/27/07.
//  Copyright 2007 MacStorm. All rights reserved.
//

#if !defined(RXERRORS_H)
#define RXERRORS_H

#include <sys/cdefs.h>

__BEGIN_DECLS

#import <Foundation/Foundation.h>
#import "PHSErrorMacros.h"


enum {
    kRXErrEditionCantBecomeCurrent = 1,
    kRXErrSavedGameCantBeLoaded,
    kRXErrArchiveUnavailable,
    kRXErrNoCurrentEdition,
    kRXErrQuickTimeTooOld,
};

extern NSString* const RXErrorDomain;

extern NSException* RXArchiveManagerArchiveNotFoundExceptionWithArchiveName(NSString* name);

__END_DECLS

#endif // RXERRORS_H
