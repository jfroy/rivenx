//
//	RXCardDescriptor.m
//	rivenx
//
//	Created by Jean-Francois Roy on 29/01/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import "RXCardDescriptor.h"
#import "RXStack.h"

#import "Additions/integer_pair_hash.h"

struct _RXCardDescriptorPrimer {
	MHKArchive* archive;
	NSData* data;
};


@implementation RXSimpleCardDescriptor

- (id)initWithStackName:(NSString*)name ID:(uint16_t)ID {
	self = [super init];
	if (!self) return nil;
	
	parentName = [name copy];
	cardID = ID;
	
	return self;
}

- (id)initWithString:(NSString*)stringRepresentation {
	self = [super init];
	if (!self) return nil;
	
	NSArray* components = [stringRepresentation componentsSeparatedByString:@" "];
	parentName = [[components objectAtIndex:0] retain];
	cardID = [[components objectAtIndex:1] intValue];
	
	return self;
}

- (id)initWithCoder:(NSCoder*)decoder {
	if (![decoder containsValueForKey:@"parent"]) {
		[self release];
		return nil;
	}
	parentName = [[decoder decodeObjectForKey:@"parent"] retain];

	if (![decoder containsValueForKey:@"ID"]) {
		[self release];
		return nil;
	}
	cardID = (uint16_t)[decoder decodeInt32ForKey:@"ID"];
	
	return self;
}

- (void)encodeWithCoder:(NSCoder*)encoder {
	if (![encoder allowsKeyedCoding]) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"RXCardDescriptor only supports keyed archiving." userInfo:nil];
	
	[encoder encodeObject:parentName forKey:@"parent"];
	[encoder encodeInt32:cardID forKey:@"ID"];
}

- (id)copyWithZone:(NSZone*)zone {
	RXSimpleCardDescriptor* new = [[RXSimpleCardDescriptor allocWithZone:zone] initWithStackName:parentName ID:cardID];
	return new;
}

- (void)dealloc {
	[parentName release];
	[super dealloc];
}

- (NSUInteger)hash {
	// WARNING: WILL BREAK ON 64-BIT
	return integer_pair_hash((int)[parentName hash], (int)cardID);
}

- (BOOL)isEqual:(id)object {
	if ([self class] != [object class]) return NO;
	return ([parentName isEqual:((RXSimpleCardDescriptor*)object)->parentName] && cardID == ((RXSimpleCardDescriptor*)object)->cardID) ? YES : NO;
}

- (NSString*)parentName {
	return parentName;
}

- (uint16_t)cardID {
	return cardID;
}

@end

@interface RXStack (RXCardDescriptor)
- (struct _RXCardDescriptorPrimer)_cardPrimerWithID:(uint16_t)cardResourceID;
@end

@implementation RXStack (RXCardDescriptor)

- (struct _RXCardDescriptorPrimer)_cardPrimerWithID:(uint16_t)cardResourceID {
	NSEnumerator* dataArchivesEnum = [_dataArchives objectEnumerator];
	MHKArchive* archive = nil;
	
	NSData* data = nil;
	while ((archive = [dataArchivesEnum nextObject])) {
		MHKFileHandle* fh = [archive openResourceWithResourceType:@"CARD" ID:cardResourceID];
		if (!fh) continue;
		
		// FIXME: check that file size doesn't overflow size_t
		size_t bufferLength = (size_t)[fh length];
		void* buffer = malloc(bufferLength);
		if (!buffer) continue;
		
		// read the data from the archive
		NSError* error;
		if ([fh readDataToEndOfFileInBuffer:buffer error:&error] == -1)
			continue;
		
		data = [NSData dataWithBytesNoCopy:buffer length:bufferLength freeWhenDone:YES];
		if (data)
			break;
	}
	
	struct _RXCardDescriptorPrimer primer = {archive, data};
	return primer;
}

@end


@implementation RXCardDescriptor

+ (id)descriptorWithStack:(RXStack *)stack ID:(uint16_t)cardID {
	return [[[RXCardDescriptor alloc] initWithStack:stack ID:cardID] autorelease];
}

- (id)init {
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (id)initWithStack:(RXStack *)stack ID:(uint16_t)cardID {
	self = [super init];
	if (!self) return nil;
	
	// try to get a primer
	struct _RXCardDescriptorPrimer primer = [stack _cardPrimerWithID:cardID];
	if (primer.data == nil) {
		[self release];
		return nil;
	}
	
	// WARNING: weak reference to the stack and archive
	_parent = stack;
	_ID = cardID;
	
	_archive = primer.archive;
	_data = [primer.data retain];
	
	// FIXME: add methods to query the stack about its name
	_name = [[[NSNumber numberWithUnsignedShort:_ID] stringValue] retain];
	
	return self;
}

- (void)dealloc {
	[_data release];
	[_name release];
	[super dealloc];
}

- (NSString *)description {
	return [NSString stringWithFormat: @"%@ %03hu", [_parent key], _ID];
}

- (RXStack*)parent {
	return _parent;
}

- (uint16_t)ID {
	return _ID;
}

- (RXSimpleCardDescriptor*)simpleDescriptor {
	if (_simpleDescriptor) return _simpleDescriptor;
	_simpleDescriptor = [[RXSimpleCardDescriptor alloc] initWithStackName:[_parent key] ID:_ID];
	return _simpleDescriptor;
}

@end
