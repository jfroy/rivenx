//
//  RXSimpleCardDescriptor_test.m
//  rivenx
//
//  Created by Jean-Francois Roy on 13/06/08.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "RXSimpleCardDescriptor_test.h"


@implementation RXSimpleCardDescriptor_test

- (void)setUp {
    _descriptor = [[RXSimpleCardDescriptor alloc] initWithStackKey:@"foo" ID:123];
}

- (void)testArchiving {
    NSData* archive = [NSKeyedArchiver archivedDataWithRootObject:_descriptor];
    STAssertNotNil(archive, @"keyed archiving should not fail");
    
    RXSimpleCardDescriptor* clonedDescriptor = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
    STAssertEquals(_descriptor->cardID, clonedDescriptor->cardID, @"card ID should match");
    STAssertEqualObjects(_descriptor->stackKey, clonedDescriptor->stackKey, @"stack name should match");
}

- (void)testStringInit {
    RXSimpleCardDescriptor* descriptor2 = [[RXSimpleCardDescriptor alloc] initWithString:@"foo 123"];
    STAssertEqualObjects(_descriptor, descriptor2, @"descriptors should be equal");
    [descriptor2 release];
}

- (void)testEqualityAndHash {
    RXSimpleCardDescriptor* descriptor2 = [[RXSimpleCardDescriptor alloc] initWithStackKey:@"foo" ID:123];
    STAssertEqualObjects(_descriptor, descriptor2, @"descriptors should be equal");
    STAssertEquals([_descriptor hash], [descriptor2 hash], @"descriptor hashes should be equal");
    [descriptor2 release];
    
    descriptor2 = [[RXSimpleCardDescriptor alloc] initWithStackKey:@"oo" ID:123];
    STAssertFalse([_descriptor isEqual:descriptor2], @"descriptors should not be equal");
    [descriptor2 release];
    
    descriptor2 = [[RXSimpleCardDescriptor alloc] initWithStackKey:@"foo" ID:1];
    STAssertFalse([_descriptor isEqual:descriptor2], @"descriptors should not be equal");
    [descriptor2 release];
    
    NSObject* foo = [NSObject new];
    STAssertFalse([_descriptor isEqual:foo], @"descriptor should not be equal to random object");
    [foo release];
}

@end
