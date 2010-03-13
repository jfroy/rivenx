//
//  RXVersionComparator.m
//  rivenx
//
//  Created by Jean-Francois Roy on 15/06/08.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "RXVersionComparator.h"


@implementation RXVersionComparator

/*!
    @method     
    @abstract   An abstract method to compare two version strings.
    @discussion Should return NSOrderedAscending if b > a, NSOrderedDescending if b < a, and NSOrderedSame if they are equivalent.
*/
- (NSComparisonResult)compareVersion:(NSString *)versionA toVersion:(NSString *)versionB {
    // numeric version reset with the switch to bzr, which are identifid by a "bzr " prefix to the numerical version
    BOOL isVersionABZR = [versionA hasPrefix:@"bzr "];
    BOOL isVersionBBZR = [versionB hasPrefix:@"bzr "];
    
    // easy cases: if B is bzr and A is not, b > a; if B is not bzr and A is, b < a; else we need to compare the versions (either both are bzr or both are not)
    if (isVersionBBZR && !isVersionABZR)
        return NSOrderedAscending;
    else if (!isVersionBBZR && isVersionABZR)
        return NSOrderedDescending;
    else {
        int a = [[versionA substringFromIndex:4] intValue];
        int b = [[versionB substringFromIndex:4] intValue];
        if (b > a)
            return NSOrderedAscending;
        else if (b == a)
            return NSOrderedSame;
        else
            return NSOrderedDescending;
    }
}

@end
