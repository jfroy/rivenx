//
//  RXErrorMacros.h
//  rivenx
//

#if !defined(RX_ERROR_MACROS_H)
#define RX_ERROR_MACROS_H

#import <errno.h>
#import <Foundation/NSError.h>

#ifndef RX_ERROR_CLASS
#define RX_ERROR_CLASS NSError
#endif

#define ReturnWithError(errorDomain, errorCode, errorInfo, errorPtr)                                     \
  do {                                                                                                   \
    if ((errorPtr))                                                                                      \
      *(errorPtr) = [RX_ERROR_CLASS errorWithDomain:(errorDomain)code:(errorCode)userInfo:(errorInfo)];  \
    return;                                                                                              \
  } while (0)

#define ReturnValueWithError(value, errorDomain, errorCode, errorInfo, errorPtr)                         \
  do {                                                                                                   \
    if ((errorPtr))                                                                                      \
      *(errorPtr) = [RX_ERROR_CLASS errorWithDomain:(errorDomain)code:(errorCode)userInfo:(errorInfo)];  \
    return (value);                                                                                      \
  } while (0)

#define ReturnValueWithError2(VALUE, CLASS, DOMAIN, CODE, INFO, PTR)                                     \
  do {                                                                                                   \
    if ((PTR))                                                                                           \
      *(PTR) = [CLASS errorWithDomain:(DOMAIN)code:(CODE)userInfo:(INFO)];                               \
    return (VALUE);                                                                                      \
  } while (0)

#define SetErrorToPOSIXError(errorInfo, errorPtr)                                                        \
  do {                                                                                                   \
    if ((errorPtr))                                                                                      \
      *(errorPtr) = [RX_ERROR_CLASS errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:(errorInfo)]; \
  } while (0)

#define ReturnWithPOSIXError(errorInfo, errorPtr)                                                        \
  do {                                                                                                   \
    SetErrorToPOSIXError((errorInfo), (errorPtr());                                                      \
    return;                                                                                              \
  } while (0)

#define ReturnValueWithPOSIXError(value, errorInfo, errorPtr)                                            \
  do {                                                                                                   \
    SetErrorToPOSIXError((errorInfo), (errorPtr));                                                       \
    return (value);                                                                                      \
  } while (0)

#endif // RX_ERROR_MACROS_H
