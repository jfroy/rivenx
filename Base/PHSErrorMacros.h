//
//  PHSErrorMacros.h
//  phascolarctidae
//
//  Created by Jean-Francois Roy on 5/21/2005.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#if defined(__OBJC__)

#if !defined(ERROR_CLASS)
#define ERROR_CLASS NSError
#endif

#define ReturnWithError(errorDomain, errorCode, errorInfo, errorPtr)                                                        \
    do {                                                                                                                    \
        if ((errorPtr)) *(errorPtr) = [ERROR_CLASS errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];    \
        return;                                                                                                             \
    } while(0)

#define ReturnWithPOSIXError(errorInfo, errorPtr)                                                                           \
    do {                                                                                                                    \
        if ((errorPtr)) *(errorPtr) = [ERROR_CLASS errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:(errorInfo)];     \
        return;                                                                                                             \
    } while(0)

#define ReturnValueWithError(value, errorDomain, errorCode, errorInfo, errorPtr)                                            \
    do {                                                                                                                    \
        if ((errorPtr)) *(errorPtr) = [ERROR_CLASS errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];    \
        return (value);                                                                                                     \
    } while(0)

#define ReturnValueWithPOSIXError(value, errorInfo, errorPtr)                                                               \
    do {                                                                                                                    \
        if ((errorPtr)) *(errorPtr) = [ERROR_CLASS errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:(errorInfo)];     \
        return (value);                                                                                                     \
    } while(0)

#define ReturnNULLWithError(errorDomain, errorCode, errorInfo, errorPtr)                                                    \
    do {                                                                                                                    \
        if ((errorPtr)) *(errorPtr) = [ERROR_CLASS errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];    \
        return NULL;                                                                                                        \
    } while(0)

#define ReturnNILWithError(errorDomain, errorCode, errorInfo, errorPtr)                                                     \
    do {                                                                                                                    \
        if ((errorPtr)) *(errorPtr) = [ERROR_CLASS errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];    \
        return nil;                                                                                                         \
    } while(0)

#define ReturnFromInitWithError(errorDomain, errorCode, errorInfo, errorPtr)                                                \
    do {                                                                                                                    \
        if ((errorPtr)) *(errorPtr) = [ERROR_CLASS errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];    \
        [self release];                                                                                                     \
        return nil;                                                                                                         \
    } while(0)

#endif // __OBJC__
