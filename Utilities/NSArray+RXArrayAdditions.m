//
//  NSArray+RXArrayAdditions.m
//  rivenx
//
//  Created by Jean-François Roy on 26/12/2011.
//  Copyright (c) 2012 MacStorm. All rights reserved.
//

#import "NSArray+RXArrayAdditions.h"


@implementation NSArray (RXArrayAdditions)

- (id)objectAtIndexIfAny:(NSUInteger)index
{
    if ([self count] <= index)
        return nil;
    return [self objectAtIndex:index];
}

@end
