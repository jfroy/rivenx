/* FScriptFunctions.h Copyright (c) 1998-2006 Philippe Mougin.  */
/*   This software is open source. See the license.  */  
 
#import <Foundation/Foundation.h>

extern NSString *FSExecutionErrorException; 
extern NSString *FSUserAbortedException; 

void  FSVerifClassArgs(NSString *methodName, int nbArgrs, ...);       
void  FSVerifClassArgsNoNil(NSString *methodName, int nbArgrs, ...);  

void  FSArgumentError(id argument, int index, NSString *expectedClass, NSString *methodName) __attribute__ ((noreturn)); 

void  FSExecError(NSString *errorStr) __attribute__ ((noreturn));

void  FSUserAborted() __attribute__ ((noreturn));
