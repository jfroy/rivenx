//
//	RXThreadUtilities.m
//	rivenx
//
//	Created by Jean-Francois Roy on 12/10/2007.
//	Copyright 2007 MacStorm. All rights reserved.
//

#import <QuickTime/QuickTime.h>

#import "RXThreadUtilities.h"
#import "RXLogging.h"
#import "InterThreadMessaging.h"

static BOOL rx_threading_initialized = NO;

static void _RXReleaseThreadStorage(void* p) {
	struct rx_thread_storage* storage = (struct rx_thread_storage*)p;
	if (storage->name) [storage->name release];
	if (storage->pool) [storage->pool release];
	free(storage);
}

struct rx_thread_storage* _RXCreateThreadStorage() {
	struct rx_thread_storage* storage = calloc(1, sizeof(struct rx_thread_storage));
	pthread_setspecific(rx_thread_storage_key, storage);
	return storage;
}

void RXInitThreading() {
	if (!pthread_main_np()) {
		RXLog(kRXLoggingBase, kRXLoggingLevelCritical, @"RXInitThreading must be called on the main thread");
		abort();
	}
	if (rx_threading_initialized == YES) return;
	rx_threading_initialized = YES;
	
	pthread_key_create(&rx_thread_storage_key, _RXReleaseThreadStorage);
}

NSString* RXGetThreadName(void) {
	return RXGetThreadStorage()->name;
}

void RXSetThreadName(NSString* name) {
	RXGetThreadStorage()->name = [name copy];
}

const char* RXGetThreadNameC(void) {
	NSString* name = RXGetThreadName();
	if (name) return [name UTF8String];
	return NULL;
}

void RXSetThreadNameC(const char* name) {
	NSString* obj_name = [[NSString alloc] initWithUTF8String:name];
	RXSetThreadName(obj_name);
	[obj_name release];
}

static void _rx_thread_pool_drain(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void* info) {
	NSAutoreleasePool* p = RXGetThreadStorage()->pool;
	RXGetThreadStorage()->pool = [NSAutoreleasePool new];
	[p release];
}

void RXThreadRunLoopRun(semaphore_t ready_semaphore, NSString* name) {
	NSAutoreleasePool* p = [NSAutoreleasePool new];
	
	// inter-thread messaging
	[NSThread prepareForInterThreadMessages];
	semaphore_signal(ready_semaphore);
	
	// set the thread name
	RXSetThreadName(name);
	
	// init QuickTime on this thread (as a precaution)
	EnterMoviesOnThread(kCSAcceptAllComponentsMode);
	
	// install per-cycle pool recycling
	RXGetThreadStorage()->pool = [NSAutoreleasePool new];
	CFRunLoopObserverContext context = {0, NULL, NULL, NULL, NULL};
	CFRunLoopObserverRef poolObserver = CFRunLoopObserverCreate(NULL, kCFRunLoopBeforeWaiting, true, 0, _rx_thread_pool_drain, &context);
	CFRunLoopAddObserver([[NSRunLoop currentRunLoop] getCFRunLoop], poolObserver, kCFRunLoopCommonModes);
	CFRelease(poolObserver);
	
	// add a dummy port on the thread so the run loop doesn't exit
	NSPort* dummy = [NSPort new];
	[dummy scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[dummy release];
	
	// run the runloop inside a try-catch context
	@try {
		[[NSRunLoop currentRunLoop] run];
	} @catch (NSException* e) {
		NSError* error = [[e userInfo] objectForKey:NSUnderlyingErrorKey];
		if (error) RXLog(kRXLoggingBase, kRXLoggingLevelCritical, @"EXCEPTION THROWN: \"%@\", ERROR: \"%@\"", e, error);
		else RXLog(kRXLoggingBase, kRXLoggingLevelCritical, @"EXCEPTION THROWN: %@", e);
		rx_print_exception_backtrace(e);
		abort();
	}
	
	[RXGetThreadStorage()->pool release];
	
	// WARNING: this may be a bug, but apparently sometimes here the thread pool stack has gone bad, so allocate a new pool just to be on the safe side
	//NSAutoreleasePool* p = RXGetThreadStorage()->pool;
	//RXGetThreadStorage()->pool = [[NSAutoreleasePool alloc] init];
	//[p release];
	
#if defined(DEBUG)
	RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"thread is terminating");
#endif
	
	// clean up
	ExitMoviesOnThread();
	[p release];
}
