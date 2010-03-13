//
//  RXThreadUtilities.m
//  rivenx
//
//  Created by Jean-Francois Roy on 12/10/2007.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <QuickTime/QuickTime.h>

#import "Debug/RXDebug.h"
#import "Base/RXThreadUtilities.h"
#import "Base/RXLogging.h"
#import "Utilities/InterThreadMessaging.h"
#import "Utilities/GTMSystemVersion.h"

static pthread_key_t rx_thread_storage_key = 0;

static void _RXReleaseThreadStorage(void* p) {
    struct rx_thread_storage* storage = (struct rx_thread_storage*)p;
    if (storage->name)
        free(storage->name);
    free(storage);
}

static struct rx_thread_storage* _RXCreateThreadStorage() {
    struct rx_thread_storage* storage = calloc(1, sizeof(struct rx_thread_storage));
    pthread_setspecific(rx_thread_storage_key, storage);
    return storage;
}

struct rx_thread_storage* RXGetThreadStorage() {
    assert(rx_thread_storage_key);
    struct rx_thread_storage* storage = (struct rx_thread_storage*)pthread_getspecific(rx_thread_storage_key);
    if (storage == NULL)
        storage = _RXCreateThreadStorage();
    return storage;
}

void RXInitThreading() {
    if (!pthread_main_np()) {
        RXLog(kRXLoggingBase, kRXLoggingLevelCritical, @"RXInitThreading must be called on the main thread");
        abort();
    }
    
    // if the thread storage key is not 0, we've initialized threading
    if (rx_thread_storage_key)
        return;
    
    pthread_key_create(&rx_thread_storage_key, _RXReleaseThreadStorage);
}

char const*  RXGetThreadName(void) {
    return RXGetThreadStorage()->name;
}

void RXSetThreadName(char const* name) {
    struct rx_thread_storage* ts = RXGetThreadStorage();
    
    size_t size = strlen(name) + 1;
    if (ts->name)
        free(ts->name);
    ts->name = malloc(size);
    strlcpy(ts->name, name, size);
    
    if ([GTMSystemVersion isLeopardOrGreater]) {
        NSString* nsName = [[NSString alloc] initWithCStringNoCopy:ts->name length:size-1 freeWhenDone:NO];
        [[NSThread currentThread] setName:nsName];
        [nsName release];
    }
    
    if ([GTMSystemVersion isSnowLeopardOrGreater])
        pthread_setname_np(ts->name);
}

void RXThreadRunLoopRun(semaphore_t ready_semaphore, char const* name) {
    NSAutoreleasePool* p = [NSAutoreleasePool new];
    
    // inter-thread messaging
    [NSThread prepareForInterThreadMessages];
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
    [p release];
}
