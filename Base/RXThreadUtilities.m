//
//  RXThreadUtilities.m
//  rivenx
//
//  Created by Jean-Francois Roy on 12/10/2007.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"
#import <QuickTime/QuickTime.h>

#import "Debug/RXDebug.h"
#import "Base/RXThreadUtilities.h"
#import "Base/RXLogging.h"
#import "Utilities/InterThreadMessaging.h"

#import <AppKit/NSApplication.h>


char* RXCopyThreadName(void)
{
    char* name = malloc(128);
    name[0] = 0;
    pthread_getname_np(pthread_self(), name, 128);
    return name;
}

void RXSetThreadName(char const* name)
{
    pthread_setname_np(name);
}

void RXThreadRunLoopRun(semaphore_t ready_semaphore, char const* name)
{
    NSAutoreleasePool* p = [NSAutoreleasePool new];
    
    semaphore_signal(ready_semaphore);
    
    // set the thread name
    RXSetThreadName(name);
    
    // init QuickTime on this thread (as a precaution)
    EnterMoviesOnThread(kCSAcceptAllComponentsMode);
    
    // add a dummy port on the thread so the run loop doesn't exit
    NSPort* dummy = [NSPort new];
    [dummy scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [dummy release];
    
    // run the runloop inside a try-catch context
    @try {
        [[NSRunLoop currentRunLoop] run];
    } @catch (NSException* e) {
        [[NSApp delegate] performSelectorOnMainThread:@selector(notifyUserOfFatalException:) withObject:e waitUntilDone:NO];
    }
    
#if defined(DEBUG)
    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"thread is terminating");
#endif
    
    // clean up
    ExitMoviesOnThread();
    [p drain];
}
