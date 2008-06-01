//
//	PHSErrorMacros.h
//	phascolarctidae
//
//	Created by Jean-Francois Roy on 5/21/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <Foundation/NSError.h>

#define ReturnWithError(errorDomain, errorCode, errorInfo, errorPtr)													\
	{																													\
		if((errorPtr)) *(errorPtr) = [NSError errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];		\
		return;																											\
	}

#define ReturnWithPOSIXError(errorInfo, errorPtr)																		\
	{																													\
		if((errorPtr)) *(errorPtr) = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:(errorInfo)];		\
		return;																											\
	}

#define ReturnValueWithError(value, errorDomain, errorCode, errorInfo, errorPtr)										\
	{																													\
		if((errorPtr)) *(errorPtr) = [NSError errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];		\
		return (value);																									\
	}

#define ReturnValueWithPOSIXError(value, errorInfo, errorPtr)															\
	{																													\
		if((errorPtr)) *(errorPtr) = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:(errorInfo)];		\
		return (value);																									\
	}

#define ReturnNULLWithError(errorDomain, errorCode, errorInfo, errorPtr)												\
	{																													\
		if((errorPtr)) *(errorPtr) = [NSError errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];		\
		return NULL;																									\
	}

#define ReturnNILWithError(errorDomain, errorCode, errorInfo, errorPtr)													\
	{																													\
		if((errorPtr)) *(errorPtr) = [NSError errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];		\
		return nil;																										\
	}

#define ReturnFromInitWithError(errorDomain, errorCode, errorInfo, errorPtr)											\
	{																													\
		if((errorPtr)) *(errorPtr) = [NSError errorWithDomain:(errorDomain) code:(errorCode) userInfo:(errorInfo)];		\
		[self release];																									\
		return nil;																										\
	}

#define ReturnWithNoError(errorPtr)																						\
	{																													\
		if((errorPtr)) *(errorPtr) = nil;																				\
		return;																											\
	}

#define ReturnValueWithNoError(value, errorPtr)																			\
	{																													\
		if((errorPtr)) *(errorPtr) = nil;																				\
		return (value);																									\
	}
