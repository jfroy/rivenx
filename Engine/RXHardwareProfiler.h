//
//  RXHardwareProfiler.h
//  rivenx
//
//  Created by Jean-Francois Roy on 10/12/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface RXHardwareProfiler : NSObject {

}

+ (RXHardwareProfiler*)sharedHardwareProfiler;

- (size_t)cacheLineSize;

@end
