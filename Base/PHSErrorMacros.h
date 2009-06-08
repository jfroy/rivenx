//
//  PHSErrorMacros.h
//  phascolarctidae
//
//  Created by Jean-Francois Roy on 5/21/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#if defined(__OBJC__)

#if defined(PHS_ERROR_CLASS)
#import PHS_ERROR_CLASS##".h"
#else
#define PHS_ERROR_CLASS NSError
#import <Foundation/NSError.h>
#endif

#define ReturnWithError(errorDomain, errorCode, errorInfo, errorPtr)                                                            \
    do {                                                                                                                        \
        if ((errorPtr)) *(errorPtr) = [PHS_ERROR_CLASS errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];    \
        return;                                                                                                                 \
    } while(0)

#define ReturnWithPOSIXError(errorInfo, errorPtr)                                                                               \
    do {                                                                                                                        \
        if ((errorPtr)) *(errorPtr) = [PHS_ERROR_CLASS errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:(errorInfo)];     \
        return;                                                                                                                 \
    } while(0)

#define ReturnValueWithError(value, errorDomain, errorCode, errorInfo, errorPtr)                                                \
    do {                                                                                                                        \
        if ((errorPtr)) *(errorPtr) = [PHS_ERROR_CLASS errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];    \
        return (value);                                                                                                         \
    } while(0)

#define ReturnValueWithPOSIXError(value, errorInfo, errorPtr)                                                                   \
    do {                                                                                                                        \
        if ((errorPtr)) *(errorPtr) = [PHS_ERROR_CLASS errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:(errorInfo)];     \
        return (value);                                                                                                         \
    } while(0)

#define ReturnNULLWithError(errorDomain, errorCode, errorInfo, errorPtr)                                                        \
    do {                                                                                                                        \
        if ((errorPtr)) *(errorPtr) = [PHS_ERROR_CLASS errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];    \
        return NULL;                                                                                                            \
    } while(0)

#define ReturnNILWithError(errorDomain, errorCode, errorInfo, errorPtr)                                                         \
    do {                                                                                                                        \
        if ((errorPtr)) *(errorPtr) = [PHS_ERROR_CLASS errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];    \
        return nil;                                                                                                             \
    } while(0)

#define ReturnFromInitWithError(errorDomain, errorCode, errorInfo, errorPtr)                                                    \
    do {                                                                                                                        \
        if ((errorPtr)) *(errorPtr) = [PHS_ERROR_CLASS errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];    \
        [self release];                                                                                                         \
        return nil;                                                                                                             \
    } while(0)

#endif // __OBJC__
