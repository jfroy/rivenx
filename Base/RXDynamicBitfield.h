//
//  RXDynamicBitfield.h
//  rivenx
//
//  Created by Jean-Francois Roy on 09/08/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface RXDynamicBitfield : NSObject {
    uintptr_t* _segments;
    uintptr_t _segment_count;
}

- (BOOL)isSet:(uintptr_t)index;
- (void)set:(uintptr_t)index;
- (void)clear:(uintptr_t)index;

- (BOOL)isAllSet;
- (void)clearAll;
- (void)setAll;

- (uintptr_t)segmentCount;
- (size_t)segmentBits;

@end
