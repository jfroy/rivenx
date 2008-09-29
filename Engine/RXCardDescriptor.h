//
//	RXCardDescriptor.h
//	rivenx
//
//	Created by Jean-Francois Roy on 29/01/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MHKKit/MHKKit.h>


@class RXStack;

@interface RXSimpleCardDescriptor : NSObject <NSCoding, NSCopying> {
@public
	NSString* parentName;
	uint16_t cardID;
}

- (id)initWithStackName:(NSString*)name ID:(uint16_t)ID;
- (id)initWithString:(NSString*)stringRepresentation;

- (NSString*)parentName;
- (uint16_t)cardID;

@end

@interface RXCardDescriptor : NSObject {
	RXStack* _parent;
	uint16_t _ID;
	
	MHKArchive* _archive;
	NSData* _data;
	NSString* _name;
	
	RXSimpleCardDescriptor* _simpleDescriptor;
}

+ (id)descriptorWithStack:(RXStack *)stack ID:(uint16_t)ID;
- (id)initWithStack:(RXStack *)stack ID:(uint16_t)ID;

- (RXStack*)parent;
- (uint16_t)ID;

- (RXSimpleCardDescriptor*)simpleDescriptor;

@end
