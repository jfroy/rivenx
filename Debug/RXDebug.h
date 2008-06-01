/*
 *	RXDebug.h
 *	rivenx
 *
 *	Created by Jean-François Roy on 10/04/2007.
 *	Copyright 2007 MacStorm. All rights reserved.
 *
 */


#if defined(__OBJC__)
#import <ExceptionHandling/NSExceptionHandler.h>
extern void rx_print_exception_backtrace(NSException* e);
#endif
