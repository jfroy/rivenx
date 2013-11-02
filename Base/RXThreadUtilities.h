//
//  RXThreadUtilities.h
//  rivenx
//
//  Created by Jean-Francois Roy on 12/10/2007.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//
//

#if !defined(RXTHREADUTILITIES_H)
#define RXTHREADUTILITIES_H

#include <assert.h>
#include <pthread.h>
#include <CoreFoundation/CoreFoundation.h>

#include <mach/semaphore.h>

__BEGIN_DECLS

char* RXCopyThreadName(void);
void RXSetThreadName(char const* name);

#if defined(__OBJC__)
extern void RXThreadRunLoopRun(semaphore_t ready_semaphore, char const* name) __attribute__((noreturn));
#endif

__END_DECLS

#endif // RXTHREADUTILITIES_H
