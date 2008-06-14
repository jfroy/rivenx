//
//  RXSimpleCardDescriptor_test.m
//  rivenx
//
//  Created by Jean-Francois Roy on 13/06/08.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "RXSimpleCardDescriptor_test.h"


@implementation RXSimpleCardDescriptor_test

- (void)setUp {
	_descriptor = [[RXSimpleCardDescriptor alloc] initWithStackName:@"foo" ID:123];
}

- (void)testArchiving {
	NSData* archive = [NSKeyedArchiver archivedDataWithRootObject:_descriptor];
	STAssertNotNil(archive, @"keyed archiving should not fail");
	
	RXSimpleCardDescriptor* clonedDescriptor = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
	STAssertEquals(_descriptor->_ID, clonedDescriptor->_ID, @"card ID should match");
	STAssertEqualObjects(_descriptor->_parentName, clonedDescriptor->_parentName, @"stack name should match");
}

@end
