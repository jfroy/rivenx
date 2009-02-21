//
//  RXAnimation_test.m
//  rivenx
//
//  Created by Jean-Francois Roy on 2008-06-19.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <unistd.h>
#import <mach/task.h>

#import "RXAnimation_test.h"
#import "RXWorld.h"


@implementation RXAnimation_test

- (BOOL)animationShouldStart:(NSAnimation*)animation {
	if ([NSThread currentThread] != [[RXWorld sharedWorld] animationThread]) wrongThread = YES;
	return YES;
}

- (void)animationDidEnd:(NSAnimation*)animation {
	if ([NSThread currentThread] != [[RXWorld sharedWorld] animationThread]) wrongThread = YES;
	semaphore_signal_all(animationEndSemaphore);
}

- (void)animationDidStop:(NSAnimation*)animation {
	if ([NSThread currentThread] != [[RXWorld sharedWorld] animationThread]) wrongThread = YES;
	semaphore_signal_all(animationEndSemaphore);
}

- (float)animation:(NSAnimation*)animation valueForProgress:(NSAnimationProgress)progress {
	if ([NSThread currentThread] != [[RXWorld sharedWorld] animationThread]) wrongThread = YES;
	return progress;
}

- (void)setUp {
	animation = [[RXAnimation alloc] initWithDuration:3.0 animationCurve:NSAnimationLinear];
	[animation setDelegate:self];
	wrongThread = NO;
	
	semaphore_create(mach_task_self(), &animationEndSemaphore, SYNC_POLICY_FIFO, 0);
}

- (void)tearDown {
	[animation release];
	semaphore_destroy(mach_task_self(), animationEndSemaphore);
}

- (void)testBasicAnimation {
	[animation startAnimation];
	semaphore_wait(animationEndSemaphore);
	STAssertFalse(wrongThread, @"animation ran some method on a thread other than the animation thread");
}

- (void)testStopAnimation {
	[animation startAnimation];
	sleep(1);
	[animation stopAnimation];
	semaphore_wait(animationEndSemaphore);
	STAssertFalse(wrongThread, @"animation ran some method on a thread other than the animation thread");
}

@end
