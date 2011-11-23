/*
 *  RXDebug.m
 *  rivenx
 *
 *  Created by Jean-François Roy on 10/04/2007.
 *  Copyright 2005-2010 MacStorm. All rights reserved.
 *
 */

#import "Base/RXBase.h"
#import "Base/RXLogging.h"
#import "Debug/RXDebug.h"

#import <Foundation/NSException.h>
#import <Foundation/NSScanner.h>
#import <Foundation/NSTask.h>


void rx_print_exception_backtrace(NSException* e)
{
    NSArray* stack = [[[e userInfo] objectForKey:NSStackTraceKey] componentsSeparatedByString:@"  "];
    if (!stack && [e respondsToSelector:@selector(callStackReturnAddresses)])
        stack = [e callStackReturnAddresses];
    
    if (stack)
    {
        // sometimes, the value 0x1 makes its way as the last call stack return address; ignore it
        if ([[stack lastObject] isKindOfClass:[NSString class]])
        {
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
        
        NSEnumerator* stack_enum = [stack objectEnumerator];
        id stack_p;
        while ((stack_p = [stack_enum nextObject]))
        {
            if ([stack_p isKindOfClass:[NSString class]])
                [args addObject:stack_p];
            else
                [args addObject:[NSString stringWithFormat:@"0x%x", [stack_p unsignedLongValue]]];
        }
        
        [ls setLaunchPath:@"/usr/bin/atos"];
        [ls setArguments:args];
        @try
        {
            [ls launch];
        }
        @catch (NSException* e)
        {
            RXLog(kRXLoggingBase, kRXLoggingLevelCritical, @"FAILED TO LAUNCH atos TO SYMBOLIFICATE EXCEPTION BACKTRACE: %@", [e description]);
            NSString* string_stack = [[args subarrayWithRange:NSMakeRange(2, [args count] - 2)] componentsJoinedByString:@"\n"];
            RXLog(kRXLoggingBase, kRXLoggingLevelCritical, @"%@", string_stack);
        }
        [ls release];
    }
    else
        RXLog(kRXLoggingBase, kRXLoggingLevelCritical, @"NO BACKTRACE AVAILABLE");
}
