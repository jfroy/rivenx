//
//	RXThreadUtilities.h
//	rivenx
//
//	Created by Jean-Francois Roy on 12/10/2007.
//	Copyright 2007 MacStorm. All rights reserved.
//
//

#if !defined(RXTHREADUTILITIES_H)
#define RXTHREADUTILITIES_H

#include <assert.h>
#include <pthread.h>
#include <CoreFoundation/CoreFoundation.h>

#include <mach/semaphore.h>

__BEGIN_DECLS

struct rx_thread_storage {
	NSString* name;
};
typedef struct rx_thread_storage rx_thread_storage_t;

extern void RXInitThreading();

extern struct rx_thread_storage* RXGetThreadStorage();

extern const char* RXGetThreadNameC(void);
extern void RXSetThreadNameC(const char* name);

#if defined(__OBJC__)
extern NSString* RXGetThreadName(void);
extern void RXSetThreadName(NSString* name);

extern void RXThreadRunLoopRun(semaphore_t ready_semaphore, NSString* name);
#endif

__END_DECLS

#endif // RXTHREADUTILITIES_H
