//
//  RXEditionProxy.m
//  rivenx
//
//  Created by Jean-Francois Roy on 05/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "RXEditionProxy.h"


@implementation RXEditionProxy

- (id)initWithEdition:(RXEdition*)e {
	self = [super init];
	if (!self)
		return nil;
	
	edition = [e retain];
	return self;
}

- (void)dealloc {
	[edition release];
	[super dealloc];
}

- (id)copyWithZone:(NSZone*)zone {
	RXEditionProxy* new = [[RXEditionProxy allocWithZone:zone] initWithEdition:edition];
	return new;
}

- (BOOL)isEqual:(id)object {
	if ([self class] != [object class])
		return NO;
	return [edition isEqual:((RXEditionProxy*)object)->edition];
}

- (NSUInteger)hash {
	return [edition hash];
}

- (RXEdition*)edition {
	return edition;
}

- (id)valueForKey:(NSString*)key {
	if ([key isEqualToString:@"edition"])
		return edition;
	return [edition valueForKey:key];
}

@end
