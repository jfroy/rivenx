//
//  RXHardwareProfiler.m
//  rivenx
//
//  Created by Jean-Francois Roy on 10/12/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import <sys/types.h>
#import <sys/sysctl.h>

#import "RXHardwareProfiler.h"


@implementation RXHardwareProfiler

+ (size_t)cacheLineSize
{
    uint64_t cache_line_size = 0;
    size_t len = sizeof(uint64_t);
    int err = sysctlbyname("hw.cachelinesize", (void*)&cache_line_size, &len, NULL, 0);
    if (err)
        return 128;
    return (size_t)cache_line_size;
}

@end
