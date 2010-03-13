//
//  RXSound_test.m
//  rivenx
//
//  Created by Jean-Francois Roy on 20/03/08.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "RXSound_test.h"
#import "RXSoundGroup.h"


@implementation RXSound_test

- (void)testRXSoundEquality {
    RXStack* a = (RXStack*)[NSString stringWithFormat:@"%@", @"astack"];
    RXStack* b = (RXStack*)[NSString stringWithFormat:@"%@", @"bstack"];
    RXSound* s1;
    RXSound* s2;
    
    s1 = [RXSound new];
    STAssertNotNil(s1, @"s1 should not be nil");
    s1->twav_id = 1;
    s1->parent = a;
    
    // test inequality based on parent
    s2 = [RXSound new];
    STAssertNotNil(s2, @"s2 should not be nil");
    s2->twav_id = 1;
    s2->parent = b;
    
    STAssertFalse([s1 isEqual:s2], @"s1 should not be equal to s2");
    
    [s2 release];
    
    // test inequality based on parent pointer
    s2 = [RXSound new];
    STAssertNotNil(s2, @"s2 should not be nil");
    s2->twav_id = 1;
    s2->parent = (RXStack*)[NSString stringWithFormat:@"%@", @"astack"];
    
    STAssertFalse([s1 isEqual:s2], @"s1 should not be equal to s2");
    
    [s2 release];
    
    // test inequality based on ID
    s2 = [RXSound new];
    STAssertNotNil(s2, @"s2 should not be nil");
    s2->twav_id = 2;
    s2->parent = a;
    
    STAssertFalse([s1 isEqual:s2], @"s1 should not be equal to s2");
    
    [s2 release];
    
    // test self equality
    STAssertTrue([s1 isEqual:s1], @"s1 should be equal to s1");
    
    // test ID and parent equality
    s2 = [RXSound new];
    STAssertNotNil(s2, @"s2 should not be nil");
    s2->twav_id = 1;
    s2->parent = a;
    
    STAssertTrue([s1 isEqual:s2], @"s1 should be equal to s2");
    
    [s2 release];
    [s1 release];
}

- (void)testRXSoundHash {
    RXStack* a = (RXStack*)[NSString stringWithFormat:@"%@", @"astack"];
    RXSound* s1;
    RXSound* s2;
    
    s1 = [RXSound new];
    STAssertNotNil(s1, @"s1 should not be nil");
    s1->twav_id = 1;
    s1->parent = a;
    
    // test self hash equality
    STAssertTrue([s1 hash] == [s1 hash], @"s1's hash should be equal to s1's hash");
    
    // test ID and parent equality
    s2 = [RXSound new];
    STAssertNotNil(s2, @"s2 should not be nil");
    s2->twav_id = 1;
    s2->parent = a;
    
    STAssertTrue([s1 hash] == [s2 hash], @"s1's hash should be equal to s2's hash");
    
    [s2 release];
    [s1 release];
}

@end
