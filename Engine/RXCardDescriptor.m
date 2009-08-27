//
//  RXCardDescriptor.m
//  rivenx
//
//  Created by Jean-Francois Roy on 29/01/2006.
//  Copyright 2006 MacStorm. All rights reserved.
//

#import "RXCardDescriptor.h"
#import "RXStack.h"

#import "Utilities/integer_pair_hash.h"

struct _RXCardDescriptorPrimer {
    MHKArchive* archive;
    NSData* data;
};


@implementation RXSimpleCardDescriptor

- (id)initWithStackKey:(NSString*)name ID:(uint16_t)ID {
    self = [super init];
    if (!self)
        return nil;
    
    stackKey = [name copy];
    cardID = ID;
    
    return self;
}

- (id)initWithString:(NSString*)stringRepresentation {
    self = [super init];
    if (!self)
        return nil;
    
    NSArray* components = [stringRepresentation componentsSeparatedByString:@" "];
    stackKey = [[components objectAtIndex:0] retain];
    cardID = [[components objectAtIndex:1] intValue];
    
    return self;
}

- (id)initWithCoder:(NSCoder*)decoder {
    stackKey = [[decoder decodeObjectForKey:@"stack"] retain];
    if (!stackKey)
        stackKey = [[decoder decodeObjectForKey:@"parent"] retain];
    if (!stackKey) {
        [self release];
        return nil;
    }

    if (![decoder containsValueForKey:@"ID"]) {
        [self release];
        return nil;
    }
    cardID = (uint16_t)[decoder decodeInt32ForKey:@"ID"];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder*)encoder {
    if (![encoder allowsKeyedCoding])
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"RXCardDescriptor only supports keyed archiving." userInfo:nil];
    
    [encoder encodeObject:stackKey forKey:@"stack"];
    [encoder encodeInt32:cardID forKey:@"ID"];
}

- (id)copyWithZone:(NSZone*)zone {
    RXSimpleCardDescriptor* new = [[RXSimpleCardDescriptor allocWithZone:zone] initWithStackKey:stackKey ID:cardID];
    return new;
}

- (void)dealloc {
    [stackKey release];
    [super dealloc];
}

- (NSUInteger)hash {
    return integer_pair_hash((int)[stackKey hash], (int)cardID);
}

- (BOOL)isEqual:(id)object {
    if ([self class] != [object class])
        return NO;
    return ([stackKey isEqualToString:((RXSimpleCardDescriptor*)object)->stackKey] &&
            cardID == ((RXSimpleCardDescriptor*)object)->cardID) ? YES : NO;
}

- (NSString*)stackKey {
    return stackKey;
}

- (uint16_t)cardID {
    return cardID;
}

@end


@implementation RXCardDescriptor

+ (id)descriptorWithStack:(RXStack*)stack ID:(uint16_t)cardID {
    return [[[RXCardDescriptor alloc] initWithStack:stack ID:cardID] autorelease];
}

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithStack:(RXStack*)stack ID:(uint16_t)cardID {
    self = [super init];
    if (!self)
        return nil;
    
    // NOTE: weak reference to the stack
    _parent = stack;
    _ID = cardID;
    
    _data = [[_parent dataWithResourceType:@"CARD" ID:_ID] retain];
    if (!_data) {
        [self release];
        return nil;
    }
    
    // get the card's name
    int16_t name_id = (int16_t)CFSwapInt16BigToHost(*(int16_t*)[_data bytes]);
    _name = (name_id >= 0) ? [_parent cardNameAtIndex:name_id] : nil;
    if (!_name)
        _name = [[NSString alloc] initWithFormat: @"%@ %03hu", [_parent key], _ID];
    else
        _name = [[NSString alloc] initWithFormat: @"%@ (%@ %03hu)", _name, [_parent key], _ID];
    
    return self;
}

- (void)dealloc {
    [_data release];
    [_name release];
    [_simpleDescriptor release];
    [super dealloc];
}

- (NSString*)description {
    return [[_name retain] autorelease];
}

- (RXStack*)parent {
    return [[_parent retain] autorelease];
}

- (uint16_t)ID {
    return _ID;
}

- (NSString*)name {
    return [[_name retain] autorelease];
}

- (uint32_t)rmap {
    return [_parent cardRMAPCodeFromID:_ID];
}

- (NSData*)data {
    return [[_data retain] autorelease];
}

- (RXSimpleCardDescriptor*)simpleDescriptor {
    if (!_simpleDescriptor)
        _simpleDescriptor = [[RXSimpleCardDescriptor alloc] initWithStackKey:[_parent key] ID:_ID];
    return [[_simpleDescriptor retain] autorelease];
}

- (BOOL)isCardWithRMAP:(uint32_t)rmap stackName:(NSString*)stack_name {
    return ([self rmap] == rmap && [[_parent key] isEqualToString:stack_name]) ? YES : NO;
}

@end
