//
//  RXThreadUtilities.m
//  rivenx
//
//  Created by Jean-Francois Roy on 12/10/2007.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"

#import <pthread.h>

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSRunLoop.h>

#if !defined(__LP64__)
#import <QuickTime/QuickTime.h>
#endif

#import "Base/RXThreadUtilities.h"

char* RXCopyThreadName(void)
{
  char* name = malloc(128);
  name[0] = 0;
  pthread_getname_np(pthread_self(), name, 128);
  return name;
}

void RXSetThreadName(char const* name) { pthread_setname_np(name); }

void RXThreadRunLoopRun(semaphore_t ready_semaphore, char const* name)
{
  if (ready_semaphore != SEMAPHORE_NULL)
    semaphore_signal(ready_semaphore);

  // set the thread name
  RXSetThreadName(name);

  // init QuickTime on this thread (as a precaution)
#if !defined(__LP64__)
  EnterMoviesOnThread(kCSAcceptAllComponentsMode);
#endif

  // get this thread's run loop
  NSRunLoop* rl = [NSRunLoop currentRunLoop];

  // create a AR pool (which will be recycled by the loop below)
  NSAutoreleasePool* pool = [NSAutoreleasePool new];

  // keep the run loop alive with a dummy port
  NSPort* port = [NSPort port];
  [port scheduleInRunLoop:rl forMode:NSDefaultRunLoopMode];

  // run the loop, recycling the pool every iteration
  while (true) {
    [rl runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    [pool release];
    pool = [NSAutoreleasePool new];
  }
}
