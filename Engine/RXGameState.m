//
//	RXGameState.m
//	rivenx
//
//	Created by Jean-Francois Roy on 02/11/2007.
//	Copyright 2007 MacStorm. All rights reserved.
//

#import "RXGameState.h"


@implementation RXGameState

// disable automatic KVC
+ (BOOL)accessInstanceVariablesDirectly {
	return NO;
}

- (void)_initRandomValues {
	[self setShort:-2 forKey:@"aDomeCombo"];
	[self setShort:-2 forKey:@"pCorrectOrder"];
	[self setShort:-2 forKey:@"tCorrectOrder"];
	[self setShort:-2 forKey:@"jIconCorrectOrder"];
	[self setShort:-2 forKey:@"pCorrectOrder"];
}

- (id)init {
	self = [super init];
	if (!self) return nil;
	
	NSError* error = nil;
	NSData* defaultVarData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"GameVariables" ofType:@"plist"] options:0 error:&error];
	if (!defaultVarData) @throw [NSException exceptionWithName:@"RXMissingDefaultEngineVariablesException" reason:@"Unable to find GameVariables.plist." userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
	
	NSString* errorString = nil;
	_variables = [[NSPropertyListSerialization propertyListFromData:defaultVarData mutabilityOption:NSPropertyListMutableContainers format:NULL errorDescription:&errorString] retain];
	if (!_variables) @throw [NSException exceptionWithName:@"RXInvalidDefaultEngineVariablesException" reason:@"Unable to load the default engine variables." userInfo:[NSDictionary dictionaryWithObject:errorString forKey:@"RXErrorString"]];
	[errorString release];
	
	[self _initRandomValues];
	
	return self;
}

- (void)dealloc {
#if defined(DEBUG)
	// dump the game state
	[self dump];
#endif
	[_variables release];
	[super dealloc];
}

- (void)dump {
	RXOLog(@"dumping\n%@", _variables);
}

- (BOOL)dvdEdition {
	return _dvdEdition;
}

- (void)setDVDEdition:(BOOL)f {
	[self willChangeValueForKey:@"dvdEdition"];
	_dvdEdition = f;
	[self didChangeValueForKey:@"dvdEdition"];
}

- (uint16_t)unsignedShortForKey:(NSString*)key {
	key = [key lowercaseString];
	uint16_t v = 0;
	NSNumber* n = [_variables objectForKey:key];
	if (n) v = [n unsignedShortValue];
	else [self setUnsignedShort:0 forKey:key];
	return v;
}

- (int16_t)shortForKey:(NSString*)key {
	key = [key lowercaseString];
	int16_t v = 0;
	NSNumber* n = [_variables objectForKey:key];
	if (n) v = [n shortValue];
	else [self setShort:0 forKey:key];
	return v;
}

- (void)setUnsignedShort:(uint16_t)value forKey:(NSString*)key {
	key = [key lowercaseString];
#if defined(DEBUG)
	RXOLog(@"setting variable %@ to %hu", key, value);
#endif
	[self willChangeValueForKey:key];
	[_variables setObject:[NSNumber numberWithUnsignedShort:value] forKey:key];
	[self didChangeValueForKey:key];
}

- (void)setShort:(int16_t)value forKey:(NSString*)key {
	key = [key lowercaseString];
#if defined(DEBUG)
	RXOLog(@"setting variable %@ to %hd", key, value);
#endif
	[self willChangeValueForKey:key];
	[_variables setObject:[NSNumber numberWithUnsignedShort:value] forKey:key];
	[self didChangeValueForKey:key];
}

- (BOOL)isKeySet:(NSString*)key {
	key = [key lowercaseString];
	return ([_variables objectForKey:key]) ? YES : NO;
}

@end
