//
//  RXCardDescriptor.h
//  rivenx
//
//  Created by Jean-Francois Roy on 29/01/2006.
//  Copyright 2006 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MHKKit/MHKKit.h>


@class RXStack;

@interface RXSimpleCardDescriptor : NSObject <NSCoding, NSCopying> {
@public
    NSString* stackKey;
    uint16_t cardID;
}

+ (RXSimpleCardDescriptor*)descriptorWithStackName:(NSString*)name rmap:(uint32_t)rmap;

- (id)initWithStackKey:(NSString*)name ID:(uint16_t)ID;
- (id)initWithString:(NSString*)stringRepresentation;

- (NSString*)stackKey;
- (uint16_t)cardID;

@end

@interface RXCardDescriptor : NSObject {
    __weak RXStack* _parent;
    uint16_t _ID;
    uint32_t _rmap;
    
    NSData* _data;
    NSString* _name;
    
    RXSimpleCardDescriptor* _simpleDescriptor;
}

+ (id)descriptorWithStack:(RXStack*)stack ID:(uint16_t)ID;
- (id)initWithStack:(RXStack*)stack ID:(uint16_t)ID;

- (RXStack*)parent;
- (uint16_t)ID;
- (NSString*)name;
- (uint32_t)rmap;

- (NSData*)data;

- (RXSimpleCardDescriptor*)simpleDescriptor;

- (BOOL)isCardWithRMAP:(uint32_t)rmap stackName:(NSString*)stack_name;

@end
