//
//  RXDynamicBitfield.m
//  rivenx
//
//  Created by Jean-Francois Roy on 09/08/2009.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "RXDynamicBitfield.h"



@implementation RXDynamicBitfield

- (id)init {
    self = [super init];
    if (!self)
        return nil;
    
    _segment_count = 1;
    _segments = calloc(_segment_count, sizeof(uintptr_t));
    
    return self;
}

- (void)dealloc {
    free(_segments);
    [super dealloc];
}

- (void)_growTo:(uintptr_t)new_count {
    debug_assert(new_count > _segment_count);
    
    register size_t new_size = new_count * sizeof(uintptr_t);
    register size_t old_size = _segment_count * sizeof(uintptr_t);
    
    _segments = realloc(_segments, new_size);
    bzero(BUFFER_OFFSET(_segments, old_size), new_size - old_size);
    _segment_count = new_count;
}

- (BOOL)isSet:(uintptr_t)index {
    register uintptr_t segment_index = index / (sizeof(uintptr_t) << 3);
    if (segment_index >= _segment_count)
        return NO;
    return (_segments[segment_index] & (1U << (index % (sizeof(uintptr_t) << 3)))) ? YES : NO;
}

- (void)set:(uintptr_t)index {
    register uintptr_t segment_index = index / (sizeof(uintptr_t) << 3);
    if (segment_index >= _segment_count)
        [self _growTo:segment_index + 1];
    _segments[segment_index] |= 1U << (index % (sizeof(uintptr_t) << 3));
}

- (void)clear:(uintptr_t)index {
    register uintptr_t segment_index = index / (sizeof(uintptr_t) << 3);
    if (segment_index >= _segment_count)
        return;
    _segments[segment_index] &= ~(1U << (index % (sizeof(uintptr_t) << 3)));
}

- (BOOL)isAllSet {
    for (uintptr_t segment_index = 0; segment_index < _segment_count; segment_index++) {
        if (_segments[segment_index] != UINTPTR_MAX)
            return NO;
    }
    return YES;
}

- (void)clearAll {
    bzero(_segments, _segment_count * sizeof(uintptr_t));
}

- (void)setAll {
    memset(_segments, 0xFF, _segment_count * sizeof(uintptr_t));
}

- (uintptr_t)segmentCount {
    return _segment_count;
}

- (size_t)segmentBits {
    return sizeof(uintptr_t) << 3;
}

@end
