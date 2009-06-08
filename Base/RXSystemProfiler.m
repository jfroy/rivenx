//
//  RXSystemProfiler.m
//  rivenx
//
//  Created by Jean-Francois Roy on 23/03/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "GTMObjectSingleton.h"

#import "RXSystemProfiler.h"


@implementation RXSystemProfiler

GTMOBJECT_SINGLETON_BOILERPLATE(RXSystemProfiler, sharedSystemProfiler)

- (id)init {
    self = [super init];
    if (!self) return nil;
    
    return self;
}

@end
