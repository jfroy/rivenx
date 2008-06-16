//
//  RXVersionComparator.m
//  rivenx
//
//  Created by Jean-Francois Roy on 15/06/08.
//  Copyright 2008 Apple Inc.. All rights reserved.
//

#import <Sparkle/SUStandardVersionComparator.h>

#import "RXVersionComparator.h"


@implementation SUStandardVersionComparator (SUStandardVersionComparator_RivenXOverride)

+ (id<SUVersionComparison>)defaultComparator {
	static id<SUVersionComparison> defaultComparator = nil;
	if (defaultComparator == nil) defaultComparator = [[RXVersionComparator alloc] init];
	return defaultComparator;
}

@end

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
	if (isVersionBBZR && !isVersionABZR) return NSOrderedAscending;
	else if (!isVersionBBZR && isVersionABZR) return NSOrderedDescending;
	else {
		NSInteger a = [[versionA substringFromIndex:4] integerValue];
		NSInteger b = [[versionB substringFromIndex:4] integerValue];
		if (b > a) return NSOrderedAscending;
		else if (b == a) return NSOrderedSame;
		else return NSOrderedDescending;
	}
}

@end
