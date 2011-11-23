/*
 * InterThreadMessaging -- InterThreadMessaging.m
 * Created by toby on Tue Jun 19 2001.
 */

#import "InterThreadMessaging.h"


static void performSelector(SEL selector, id receiver, id object, NSThread* thread, BOOL wait)
{
    [receiver performSelector:selector onThread:thread withObject:object waitUntilDone:wait];
}

@implementation NSObject (InterThreadMessaging)

- (void)performSelector:(SEL)selector inThread:(NSThread*)thread
{
    performSelector(selector, self, nil, thread, NO);
}

- (void)performSelector:(SEL)selector inThread:(NSThread*)thread waitUntilDone:(BOOL)wait
{
    performSelector(selector, self, nil, thread, wait);
}

- (void)performSelector:(SEL)selector withObject:(id)object inThread:(NSThread*)thread
{
    performSelector(selector, self, object, thread, NO);
}

- (void)performSelector:(SEL)selector withObject:(id)object inThread:(NSThread*)thread waitUntilDone:(BOOL)wait
{
    performSelector(selector, self, object, thread, wait);
}

@end
