//
//	RXGameState.m
//	rivenx
//
//	Created by Jean-Francois Roy on 02/11/2007.
//	Copyright 2007 MacStorm. All rights reserved.
//

#import "RXGameState.h"
#import "RXEditionManager.h"


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
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (id)initWithEdition:(RXEdition*)edition {
	self = [super init];
	if (!self) return nil;
	
	if (edition == nil) {
		[self release];
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"edition must not be nil" userInfo:nil];
	}
	
	NSError* error = nil;
	NSData* defaultVarData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"GameVariables" ofType:@"plist"] options:0 error:&error];
	if (!defaultVarData) {
		[self release];
		@throw [NSException exceptionWithName:@"RXMissingDefaultEngineVariablesException" reason:@"Unable to find GameVariables.plist." userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
	}
	
	NSString* errorString = nil;
	_variables = [[NSPropertyListSerialization propertyListFromData:defaultVarData mutabilityOption:NSPropertyListMutableContainers format:NULL errorDescription:&errorString] retain];
	if (!_variables) {
		[self release];
		@throw [NSException exceptionWithName:@"RXInvalidDefaultEngineVariablesException" reason:@"Unable to load the default engine variables." userInfo:[NSDictionary dictionaryWithObject:errorString forKey:@"RXErrorString"]];
	}
	[errorString release];
	
	_edition = [edition retain];
	
	// a certain part of the game state is random generated; defer that work to another dedicated method
	[self _initRandomValues];
	
	// keep track of the active card
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_activeCardDidChange:) name:@"RXActiveCardDidChange" object:nil];
	
	return self;
}

- (id)initWithCoder:(NSCoder*)decoder {
	self = [super init];
	if (!self) return nil;

	if (![decoder containsValueForKey:@"VERSION"]) {
		[self release];
		return nil;
	}
	int32_t version = [decoder decodeInt32ForKey:@"VERSION"];
	
	switch (version) {
		case 0:
			if (![decoder containsValueForKey:@"editionKey"]) {
				[self release];
				@throw [NSException exceptionWithName:@"RXInvalidGameStateArchive" reason:@"Riven X does not understand this save file. It may be corrupted or may not be a Riven X save file at all." userInfo:nil];
			}
			NSString* editionKey = [decoder decodeObjectForKey:@"editionKey"];
			_edition = [[[RXEditionManager sharedEditionManager] editionForKey:editionKey] retain];
			if (_edition) {
				[self release];
				@throw [NSException exceptionWithName:@"RXUnknownEditionKeyException" reason:@"Riven X was unable to find the edition for this save file." userInfo:nil];
			}
			
			if (![decoder containsValueForKey:@"currentCard"]) {
				[self release];
				@throw [NSException exceptionWithName:@"RXInvalidGameStateArchive" reason:@"Riven X does not understand this save file. It may be corrupted or may not be a Riven X save file at all." userInfo:nil];
			}
			_currentCard = [[decoder decodeObjectForKey:@"currentCard"] retain];

			if (![decoder containsValueForKey:@"variables"]) {
				[self release];
				@throw [NSException exceptionWithName:@"RXInvalidGameStateArchive" reason:@"Riven X does not understand this save file. It may be corrupted or may not be a Riven X save file at all." userInfo:nil];
			}
			_variables = [[decoder decodeObjectForKey:@"variables"] retain];
			
			break;
		
		default:
			@throw [NSException exceptionWithName:@"RXInvalidGameStateArchive" reason:@"Riven X does not understand this save file. It may be corrupted or may not be a Riven X save file at all." userInfo:nil];
	}
	
	// keep track of the active card
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_activeCardDidChange:) name:@"RXActiveCardDidChange" object:nil];
	
	return self;
}

- (void)encodeWithCoder:(NSCoder*)encoder {
	if (![encoder allowsKeyedCoding]) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"RXGameState only supports keyed archiving." userInfo:nil];
	
	[encoder encodeInt32:0 forKey:@"VERSION"];
	
	[encoder encodeObject:[_edition key] forKey:@"editionKey"];
	[encoder encodeObject:_currentCard forKey:@"currentCard"];
	[encoder encodeObject:_variables forKey:@"variables"];
}

- (void)dealloc {
#if defined(DEBUG)
	// dump the game state
	[self dump];
#endif

	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[_edition release];
	[_variables release];
	[_currentCard release];
	
	[super dealloc];
}

- (void)dump {
	RXOLog(@"dumping\n%@", _variables);
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

- (RXSimpleCardDescriptor*)currentCard {
	return _currentCard;
}

- (void)setCurrentCard:(RXSimpleCardDescriptor*)descriptor {
	[_currentCard release];
	_currentCard = [descriptor retain];
}

- (void)_activeCardDidChange:(NSNotification*)notification {
	[self setCurrentCard:[(RXCardDescriptor*)[[notification object] descriptor] simpleDescriptor]];
}

@end
