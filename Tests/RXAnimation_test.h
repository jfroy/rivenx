//
//  RXAnimation_test.h
//  rivenx
//
//  Created by Jean-Francois Roy on 2008-06-19.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <mach/semaphore.h>

#import <SenTestingKit/SenTestingKit.h>

#import "RXAnimation.h"


@interface RXAnimation_test : SenTestCase {
    RXAnimation* animation;
    BOOL wrongThread;
    semaphore_t animationEndSemaphore;
}

@end
