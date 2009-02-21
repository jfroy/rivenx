//
//	RXEdition.m
//	rivenx
//
//	Created by Jean-Francois Roy on 02/02/2008.
//	Copyright 2008 MacStorm. All rights reserved.
//

#import "RXEdition.h"

#import "RXWorld.h"
#import "BZFSUtilities.h"

#import "RXEditionProxy.h"


@implementation RXEdition

+ (BOOL)_saneDescriptor:(NSDictionary*)descriptor {
	// a valid edition descriptor must have 3 root keys, "Edition", "Stacks" and "Stack switch table"
	if (![descriptor objectForKey:@"Edition"])
		return NO;
	if (![descriptor objectForKey:@"Stacks"])
		return NO;
	if (![descriptor objectForKey:@"Stack switch table"])
		return NO;
	if (![descriptor objectForKey:@"Journals"])
		return NO;
	
	// the Edtion sub-directionary must have a Key, a Discs and a Install Directives key
	id edition = [descriptor objectForKey:@"Edition"];
	if (![edition isKindOfClass:[NSDictionary class]])
		return NO;
	if (![edition objectForKey:@"Key"])
		return NO;
	if (![edition objectForKey:@"Discs"])
		return NO;
	if (![edition objectForKey:@"Install Directives"])
		return NO;
	if (![edition objectForKey:@"Directories"])
		return NO;
	
	// must have at least one disc
	id discs = [edition objectForKey:@"Discs"];
	if (![discs isKindOfClass:[NSArray class]])
		return NO;
	if ([discs count] == 0)
		return NO;
	
	// Directories must be a dictionary and contain at least Data, Sound and All keys
	id directories = [edition objectForKey:@"Directories"];
	if (![directories isKindOfClass:[NSDictionary class]])
		return NO;
	if (![directories objectForKey:@"Data"])
		return NO;
	if (![directories objectForKey:@"Sound"])
		return NO;
	if (![directories objectForKey:@"All"])
		return NO;
	
	// Journals must be a dictionary and contain at least a "Card ID Map" key
	id journals = [descriptor objectForKey:@"Journals"];
	if (![journals isKindOfClass:[NSDictionary class]])
		return NO;
	if (![journals objectForKey:@"Card ID Map"])
		return NO;
	
	// good enough
	return YES;
}

- (void)_determineMustInstall {
	_mustInstall = NO;
	
	NSArray* directives = [[_descriptor objectForKey:@"Edition"] objectForKey:@"Install Directives"];
	NSEnumerator* e = [directives objectEnumerator];
	NSDictionary* directive;
	while ((directive = [e nextObject])) {
		NSNumber* required = [directive objectForKey:@"Required"];
		if (required && [required boolValue]) {
			_mustInstall = YES;
			return;
		}
	}
}

- (void)_loadUserData {
	// user data is stored in a plist inside the edition user base
	NSError* error;
	NSString* userDataPath = [userBase stringByAppendingPathComponent:@"User Data.plist"];
	if (BZFSFileExists(userDataPath)) {
		NSData* userRawData = [NSData dataWithContentsOfFile:userDataPath options:0 error:&error];
		// FIXME: should be nicer than blower up, say by offering to create a new user data file and moving the old one aside, heck asking to go in Time Machine
		if (!userRawData)
			@throw [NSException exceptionWithName:@"RXCorruptedEditionUserDataException" reason:[NSString stringWithFormat:@"Your data for the %@ is corrupted.", name] userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
		_userData = [[NSPropertyListSerialization propertyListFromData:userRawData mutabilityOption:NSPropertyListMutableContainers format:NULL errorDescription:NULL] retain];
	} else {
		// create a new user data directionary
		_userData = [NSMutableDictionary new];
	}
}

- (id)init {
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (id)initWithDescriptor:(NSDictionary*)descriptor {
	self = [super init];
	if (!self) return nil;
	
	if (!descriptor || ![[self class] _saneDescriptor:descriptor]) {
		[self release];
		return nil;
	}
	
	NSError* error = nil;
	BOOL success;
	
	// keep the descriptor around
	_descriptor = [descriptor retain];
	
	// load edition information
	NSDictionary* edition = [_descriptor objectForKey:@"Edition"];
	key = [edition objectForKey:@"Key"];
	name = [NSLocalizedStringFromTable(key, @"Editions", nil) retain];
	discs = [edition objectForKey:@"Discs"];
	directories = [edition objectForKey:@"Directories"];
	installDirectives = [edition objectForKey:@"Install Directives"];
	
	NSDictionary* textSwitchTable = [_descriptor objectForKey:@"Stack switch table"];
	NSMutableDictionary* finalSwitchTable = [NSMutableDictionary new];
	
	NSEnumerator* keyEnum = [textSwitchTable keyEnumerator];
	NSString* switchKey;
	while ((switchKey = [keyEnum nextObject])) {
		RXSimpleCardDescriptor* fromDescriptor = [[RXSimpleCardDescriptor alloc] initWithString:switchKey];
		RXSimpleCardDescriptor* toDescriptor = [[RXSimpleCardDescriptor alloc] initWithString:[textSwitchTable objectForKey:switchKey]];
		[finalSwitchTable setObject:toDescriptor forKey:fromDescriptor];
		[toDescriptor release];
		[fromDescriptor release];
	}
	
	stackSwitchTables = finalSwitchTable;
	
	journalCardIDMap = [[[_descriptor objectForKey:@"Journals"] objectForKey:@"Card ID Map"] retain];
	
	// create the support directory for the edition
	// FIXME: we should offer system-wide editions as well
	userBase = [[[[[RXWorld sharedWorld] worldUserBase] path] stringByAppendingPathComponent:key] retain];
	if (!BZFSDirectoryExists(userBase)) {
		success = BZFSCreateDirectory(userBase, &error);
		if (!success)
			@throw [NSException exceptionWithName:@"RXFilesystemException" reason:[NSString stringWithFormat:@"Riven X was unable to create a support folder for the %@.", name] userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	}
	
	// sub-directory in the edition user base for data files
	// FIXME: data files should ideally not be installed per-user...
	userDataBase = [[userBase stringByAppendingPathComponent:@"Data"] retain];
	if (!BZFSDirectoryExists(userDataBase)) {
		success = BZFSCreateDirectory(userDataBase, &error);
		if (!success)
			@throw [NSException exceptionWithName:@"RXFilesystemException" reason:[NSString stringWithFormat:@"Riven X was unable to create the Data folder for the %@.", name] userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	}
	
	stackDescriptors = [_descriptor objectForKey:@"Stacks"];
	
	// determine if this edtion must be installed to play
	[self _determineMustInstall];
	
	// get the user's data for this edition
	[self _loadUserData];
	
	openArchives = [NSMutableArray new];
	
#if defined(DEBUG)
	RXOLog(@"loaded");
#endif
	return self;
}

- (NSString*)description {
	return [NSString stringWithFormat: @"%@ {name=%@}", [super description], name];
}

- (void)dealloc {
	// before dying, write our user data
	// FIXME: handle errors
	[self writeUserData:NULL];
	
	[_descriptor release];
	[_userData release];
	
	[name release];
	
	[userBase release];
	[userDataBase release];
	
	[openArchives release];
	
	[stackSwitchTables release];
	[journalCardIDMap release];
	
	[super dealloc];
}

- (RXEditionProxy*)proxy {
	return [[[RXEditionProxy alloc] initWithEdition:self] autorelease];
}

- (NSMutableDictionary*)userData {
	return _userData;
}

- (BOOL)writeUserData:(NSError**)error {
	NSString* userDataPath = [userBase stringByAppendingPathComponent:@"User Data.plist"];
	NSData* userRawData = [NSPropertyListSerialization dataFromPropertyList:_userData format:NSPropertyListBinaryFormat_v1_0 errorDescription:NULL];
	if (!userRawData) ReturnValueWithError(NO, RXErrorDomain, 0, nil, error);
	return [userRawData writeToFile:userDataPath options:NSAtomicWrite error:error];
}

- (BOOL)mustBeInstalled {
	return _mustInstall;
}

- (BOOL)isInstalled {
	return ([_userData objectForKey:@"Installation Domain"]) ? YES : NO;
}

- (BOOL)isFullInstalled {
	if (![self isInstalled]) return NO;
	NSString* type = [_userData objectForKey:@"Installation Type"];
	if (!type) return NO;
	return ([type isEqualToString:@"Full"]) ? YES : NO;
}

- (BOOL)canBecomeCurrent {
	if ([self mustBeInstalled] && ![self isInstalled]) return NO;
	return YES;
}

- (BOOL)isValidMountPath:(NSString*)path {
	if ([discs containsObject:[path lastPathComponent]] == NO) return NO;
	if (BZFSDirectoryExists([path stringByAppendingPathComponent:@"Data"]) == NO) return NO;
	return YES;
}

@end
