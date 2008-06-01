//
//  RXSystemProfiler.h
//  rivenx
//
//  Created by Jean-Francois Roy on 23/03/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface RXSystemProfiler : NSObject {
	uint32_t _systemVersion;
	uint32_t _architecture;
	uint32_t _logicalCPUs;
	uint64_t _ram;
}

+ (RXSystemProfiler*)sharedSystemProfiler;

@end
