/*
 *  RXDebug.m
 *  rivenx
 *
 *  Created by Jean-François Roy on 10/04/2007.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#import "Base/RXBase.h"
#import "Base/RXLogging.h"
#import "Debug/RXDebug.h"

#import <Foundation/NSBundle.h>
#import <Foundation/NSException.h>
#import <Foundation/NSScanner.h>
#import <Foundation/NSTask.h>

#import <AppKit/NSAlert.h>

#import <ExceptionHandling/NSExceptionHandler.h>

static void print_exception_backtrace(NSException* e)
{
  NSArray* stack = [[[e userInfo] objectForKey:NSStackTraceKey] componentsSeparatedByString:@"  "];
  if (!stack && [e respondsToSelector:@selector(callStackReturnAddresses)])
    stack = [e callStackReturnAddresses];

  if (stack) {
    // sometimes, the value 0x1 makes its way as the last call stack return address; ignore it
    if ([[stack lastObject] isKindOfClass:[NSString class]]) {
      NSScanner* scanner = [[NSScanner alloc] initWithString:[stack lastObject]];
      uint32_t address;
      [scanner scanHexInt:&address];
      if (address == 0x1)
        stack = [stack subarrayWithRange:NSMakeRange(0, [stack count] - 1)];
      [scanner release];
    }

    NSTask* ls = [[NSTask alloc] init];
    NSString* pid = [[NSNumber numberWithInt:getpid()] stringValue];
    NSMutableArray* args = [NSMutableArray arrayWithCapacity:20];

    [args addObject:@"-p"];
    [args addObject:pid];

    for (id stack_p in stack) {
      if ([stack_p isKindOfClass:[NSString class]])
        [args addObject:stack_p];
      else
        [args addObject:[NSString stringWithFormat:@"0x%lx", [stack_p unsignedLongValue]]];
    }

    [ls setLaunchPath:@"/usr/bin/atos"];
    [ls setArguments:args];
    @try { [ls launch]; }
    @catch (NSException* e)
    {
      RXLog(kRXLoggingBase, kRXLoggingLevelCritical, @"FAILED TO LAUNCH atos TO SYMBOLIFICATE EXCEPTION BACKTRACE: %@", [e description]);
      NSString* string_stack = [[args subarrayWithRange:NSMakeRange(2, [args count] - 2)] componentsJoinedByString:@"\n"];
      RXLog(kRXLoggingBase, kRXLoggingLevelCritical, @"%@", string_stack);
    }
    [ls release];
  } else {
    RXLog(kRXLoggingBase, kRXLoggingLevelCritical, @"NO BACKTRACE AVAILABLE");
  }
}

@interface RXExceptionHandlerDelegate : NSObject
@end

@implementation RXExceptionHandlerDelegate

- (void)notifyUserOfFatalException:(NSException*)e
{
  [[NSExceptionHandler defaultExceptionHandler] setExceptionHandlingMask:0];

  print_exception_backtrace(e);

  NSAlert* failureAlert = [NSAlert new];
  [failureAlert setMessageText:[e reason]];
  [failureAlert setAlertStyle:NSWarningAlertStyle];
  [failureAlert addButtonWithTitle:NSLocalizedString(@"Quit", @"quit button")];

  NSDictionary* userInfo = [e userInfo];
  if (userInfo) {
    NSError* error = [[e userInfo] objectForKey:NSUnderlyingErrorKey];
    if (error)
      [failureAlert setInformativeText:[error localizedDescription]];
    else
      [failureAlert setInformativeText:[e name]];
  } else
    [failureAlert setInformativeText:[e name]];

  [failureAlert runModal];
  [failureAlert release];

  [NSApp terminate:nil];
}

- (BOOL)shouldIgnoreException:(NSException*)exception
{
  return [[exception name] isEqualToString:@"RXCommandArgumentsException"] || [[exception name] isEqualToString:@"RXUnknownCommandException"] ||
         [[exception name] isEqualToString:@"RXCommandError"];
}

- (BOOL)exceptionHandler:(NSExceptionHandler*)sender shouldHandleException:(NSException*)exception mask:(NSUInteger)aMask
{
  if ([self shouldIgnoreException:exception])
    return NO;
  [self notifyUserOfFatalException:exception];
  return YES;
}

- (BOOL)exceptionHandler:(NSExceptionHandler*)sender shouldLogException:(NSException*)exception mask:(NSUInteger)aMask
{ return [self shouldIgnoreException:exception]; }

@end

static RXExceptionHandlerDelegate* s_exceptionHandlerDelegate = nil;

void rx_install_exception_handler(void)
{
  release_assert(s_exceptionHandlerDelegate == nil);
  s_exceptionHandlerDelegate = [RXExceptionHandlerDelegate new];
  NSExceptionHandler* handler = [NSExceptionHandler defaultExceptionHandler];
  [handler setDelegate:s_exceptionHandlerDelegate];
  [handler setExceptionHandlingMask:NSLogUncaughtExceptionMask | NSHandleUncaughtExceptionMask | NSLogUncaughtSystemExceptionMask |
                                    NSHandleUncaughtSystemExceptionMask | NSLogUncaughtRuntimeErrorMask | NSHandleUncaughtRuntimeErrorMask];
}
