//
//	RXEditionManager.m
//	rivenx
//
//	Created by Jean-Francois Roy on 02/02/2008.
//	Copyright 2008 MacStorm. All rights reserved.
//

#import <Carbon/Carbon.h>

#import "RXEditionManager.h"
#import "RXWorld.h"

#import "Utilities/BZFSUtilities.h"
#import "Utilities/GTMObjectSingleton.h"


@implementation RXEditionManager

GTMOBJECT_SINGLETON_BOILERPLATE(RXEditionManager, sharedEditionManager)

- (void)_scanMountPath:(NSString*)mp {
#if defined(DEBUG)
	RXOLog(@"scanning %@", mp);
#endif

	// the goal of this method is to check if at least one edition is interested in the new mount path
	NSEnumerator* e = [editions objectEnumerator];
	RXEdition* ed;
	while ((ed = [e nextObject])) {
		if ([ed isValidMountPath:mp]) {
			if (![_validMountPaths containsObject:mp])
				[_validMountPaths addObject:mp];
			return;
		}
	}
}

- (void)_removableMediaMounted:(NSNotification*)notification {
	NSString* mountPath = [[notification userInfo] objectForKey:@"NSDevicePath"];
	
	// scan the new mount path
	[self _scanMountPath:mountPath];
	
	// were we waiting for this disc?
	if (_waitingForThisDisc && [[mountPath lastPathComponent] isEqualToString:_waitingForThisDisc]) {
		[_waitingForThisDisc release];
		_waitingForThisDisc = nil;
	}
}

- (void)_removableMediaUnmounted:(NSNotification*)notification {
	NSString* mountPath = [[notification userInfo] objectForKey:@"NSDevicePath"];
#if defined(DEBUG)
	RXOLog(@"removable media mounted at %@ is gone", mountPath);
#endif
	
	[_validMountPaths removeObject:mountPath];
}

- (void)_initialMediaScan {
	NSArray* mountedMedia = [[NSWorkspace sharedWorkspace] mountedRemovableMedia];
	
	// search for Riven data stores
	NSEnumerator* mediaEnum = [mountedMedia objectEnumerator];
	NSString* mediaMountPath = nil;
	while ((mediaMountPath = [mediaEnum nextObject]))
		[self _scanMountPath:mediaMountPath];
}

#pragma mark -

- (BOOL)_writeSettings {
	NSString* serializationError;
	NSData* settingsData = [NSPropertyListSerialization dataFromPropertyList:_editionManagerSettings format:NSPropertyListBinaryFormat_v1_0 errorDescription:&serializationError];
	if (!settingsData)
		return NO;
	
	NSString* editionManagerSettingsPath = [[[[RXWorld sharedWorld] worldUserBase] path] stringByAppendingPathComponent:@"Edtion Manager.plist"];
	return [settingsData writeToFile:editionManagerSettingsPath options:NSAtomicWrite error:NULL];
}

#pragma mark -

- (id)init	{
	self = [super init];
	if (!self)
		return nil;
	
	editions = [NSMutableDictionary new];
	editionProxies = [NSMutableArray new];
	
	_validMountPaths = [NSMutableArray new];
	_waitingForThisDisc = nil;
	
	// find the Editions directory
	NSString* editionsDirectory = [[NSBundle mainBundle] pathForResource:@"Editions" ofType:nil];
	if (!editionsDirectory)
		@throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Riven X could not find the Editions bundle resource directory." userInfo:nil];
	
	// get its content
	NSFileManager* fm = [NSFileManager defaultManager];
	NSArray* editionPlists;
	NSError* error = nil;
	if ([fm respondsToSelector:@selector(contentsOfDirectoryAtPath:error:)])
		editionPlists = [fm contentsOfDirectoryAtPath:editionsDirectory error:&error];
	else
		editionPlists = [fm directoryContentsAtPath:editionsDirectory];
	if (!editionPlists)
		@throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Riven X could not iterate the Editions bundle resource directory." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	// iterate over its content
	NSEnumerator* e = [editionPlists objectEnumerator];
	NSString* editionPlist;
	while ((editionPlist = [e nextObject])) {
		// cache the full path
		NSString* editionPlistPath = [editionsDirectory stringByAppendingPathComponent:editionPlist];
		
		// try to allocate an edition object
		RXEdition* ed = [[RXEdition alloc] initWithDescriptor:[NSDictionary dictionaryWithContentsOfFile:editionPlistPath]];
		if (!ed)
			RXOLog(@"failed to load edition %@", editionPlist);
		else {
			[editions setObject:ed forKey:[ed valueForKey:@"key"]];
			[editionProxies addObject:[ed proxy]];
		}
		[ed release];
	}
	
	// get the location of the local data store
	_localDataStore = [[[[[RXWorld sharedWorld] worldBase] path] stringByAppendingPathComponent:@"Data"] retain];
	
#if defined(DEBUG)
	if (!BZFSDirectoryExists(_localDataStore)) {
		[_localDataStore release];
		_localDataStore = [[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"Data"] retain];
	}
#endif
	
	// check if the local data store exists (it is not required)
	if (!BZFSDirectoryExists(_localDataStore)) {
		[_localDataStore release];
		_localDataStore = nil;
#if defined(DEBUG)
		RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"no local data store could be found");
#endif
	}
	
	// do an initial scan of mounted media
	[self _initialMediaScan];
	
	// register for removable media notifications
	NSNotificationCenter* wsNotificationCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
	[wsNotificationCenter addObserver:self selector:@selector(_removableMediaMounted:) name:NSWorkspaceDidMountNotification object:nil];
	[wsNotificationCenter addObserver:self selector:@selector(_removableMediaUnmounted:) name:NSWorkspaceDidUnmountNotification object:nil];
	
	// load edition manager settings
	NSString* editionManagerSettingsPath = [[[[RXWorld sharedWorld] worldUserBase] path] stringByAppendingPathComponent:@"Edtion Manager.plist"];
	if (BZFSFileExists(editionManagerSettingsPath)) {
		NSData* settingsData = [NSData dataWithContentsOfFile:editionManagerSettingsPath options:0 error:&error];
		if (settingsData == nil)
			@throw [NSException exceptionWithName:@"RXIOException" reason:@"Riven X could not load the existing edition manager settings." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
		
		NSString* serializationError;
		_editionManagerSettings = [[NSPropertyListSerialization propertyListFromData:settingsData mutabilityOption:NSPropertyListMutableContainers format:NULL errorDescription:&serializationError] retain];
		if (_editionManagerSettings == nil)
			@throw [NSException exceptionWithName:@"RXIOException" reason:@"Riven X could not load the existing edition manager settings." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:serializationError, @"RXErrorString", nil]];
	} else
		_editionManagerSettings = [NSMutableDictionary new];
	
	// if we have an edition selection saved in the settings, try to use it; otherwise, display the edition manager; 
	// we use a performSelector because the world is not done initializing when the edition manager is initialized and we must defer the edition changed notification until the next run loop cycle
	RXEdition* defaultEdition = [self defaultEdition];
	BOOL optKeyDown = ((GetCurrentKeyModifiers() & (optionKey | rightOptionKey)) != 0) ? YES : NO;
	if (defaultEdition && !optKeyDown)
		[self performSelectorOnMainThread:@selector(_makeEditionChoiceMemoryCurrent) withObject:nil waitUntilDone:NO];
	else
		[self showEditionManagerWindow];
	
	return self;
}

- (void)tearDown {
	if (_tornDown)
		return;
	_tornDown = YES;
	
	[[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
	
	[_windowController close];
	[_windowController release];
	
	[_validMountPaths release];
	[_waitingForThisDisc release];
	
	[_localDataStore release];
}

- (void)dealloc {
	[self tearDown];
	
	[editions release];
	[editionProxies release];
	
	[super dealloc];
}

- (RXEdition*)editionForKey:(NSString*)editionKey {
	return [editions objectForKey:editionKey];
}

- (RXEdition*)currentEdition {
	return currentEdition;
}

- (void)showEditionManagerWindow {
	if (!_windowController)
		_windowController = [[RXEditionManagerWindowController alloc] initWithWindowNibName:@"EditionManager"];

	[[_windowController window] center];
	[_windowController showWindow:self];
}

- (RXEdition*)defaultEdition {
	return [editions objectForKey:[_editionManagerSettings objectForKey:@"RXEditionChoiceMemory"]];
}

- (void)setDefaultEdition:(RXEdition*)edition {
	if (edition)
		[_editionManagerSettings setObject:[edition valueForKey:@"key"] forKey:@"RXEditionChoiceMemory"];
	else
		[_editionManagerSettings removeObjectForKey:@"RXEditionChoiceMemory"];
	[self _writeSettings];
}

- (void)resetDefaultEdition {
	[self setDefaultEdition:nil];
}

- (BOOL)makeEditionCurrent:(RXEdition*)edition rememberChoice:(BOOL)remember error:(NSError**)error {
	if ([edition isEqual:currentEdition]) {
		// if we're told to remember this choice, do so
		if (remember)
			[self setDefaultEdition:edition];
		return YES;
	}

	// check that this edition can become current
	if (![edition canBecomeCurrent])
		ReturnValueWithError(NO, RXErrorDomain, kRXErrEditionCantBecomeCurrent, nil, error);
	
	// if we're told to remember this choice, do so
	if (remember)
		[self setDefaultEdition:edition];
	
	// change the current edition ivar and post the current edition changed notification
	currentEdition = edition;
	[[NSNotificationCenter defaultCenter] postNotificationName:@"RXCurrentEditionChangedNotification" object:edition];
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"made %@ the current edition", edition);
#endif
	return YES;
}

- (void)_makeEditionChoiceMemoryCurrent {
	// NOTE: WILL RUN ON THE MAIN THREAD
	NSError* error;
	
	RXEdition* defaultEdition = [self defaultEdition];
	if (!defaultEdition)
		[self showEditionManagerWindow];
	
	if (![self makeEditionCurrent:defaultEdition rememberChoice:YES error:&error]) {
		if ([error code] == kRXErrEditionCantBecomeCurrent && [error domain] == RXErrorDomain) {
			[self resetDefaultEdition];
			
			error = [NSError errorWithDomain:[error domain] code:[error code] userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
				[NSString stringWithFormat:@"Riven X cannot make \"%@\" the current edition because it is not installed.", [defaultEdition valueForKey:@"name"]], NSLocalizedDescriptionKey,
				@"You need to install this edition by using the Edition Manager.", NSLocalizedRecoverySuggestionErrorKey,
				[NSArray arrayWithObjects:@"Install", @"Quit", nil], NSLocalizedRecoveryOptionsErrorKey,
				[NSApp delegate], NSRecoveryAttempterErrorKey,
				error, NSUnderlyingErrorKey,
				nil]];
		}
		
		[NSApp presentError:error];
	}
}

#pragma mark -

- (void)_actuallyWaitForDisc:(NSString*)disc inModalSession:(NSModalSession)session {
#if defined(DEBUG)
	RXOLog(@"waiting for disc %@", disc);
#endif
	
	// as a convenience, try to eject the last known valid mount path we know about
	if ([_validMountPaths count])
		[self ejectMountPath:[_validMountPaths lastObject]];
	
	_waitingForThisDisc = [disc retain];
	while (_waitingForThisDisc) {
		if (session) {
			if ([NSApp runModalSession:session] != NSRunContinuesResponse) {
				[_waitingForThisDisc release];
				_waitingForThisDisc = nil;
			}
		}
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
	}
}

- (NSString*)mountPathForDisc:(NSString*)disc {
	return [self mountPathForDisc:disc waitingInModalSession:NULL];
}

- (NSString*)mountPathForDisc:(NSString*)disc waitingInModalSession:(NSModalSession)session {
	NSEnumerator* discEnum = [_validMountPaths objectEnumerator];
	NSString* mount;
	while ((mount = [discEnum nextObject])) {
		if ([[mount lastPathComponent] isEqualToString:disc])
			return mount;
	}
	
	// if there's a modal session, wait for the disc while driving the session
	if (session) {
		[self _actuallyWaitForDisc:disc inModalSession:session];
		mount = [self mountPathForDisc:disc waitingInModalSession:NULL];
	}
	
	return mount;
}

- (void)ejectMountPath:(NSString*)mountPath {
	// don't ask questions, someone doesn't like it
	[[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtPath:mountPath];
}

- (MHKArchive*)_archiveWithFilename:(NSString*)filename directoryKey:(NSString*)dirKey stackID:(NSString*)stackID error:(NSError**)error {
	NSString* archivePath;
	MHKArchive* archive = nil;
	
	// FIXME: this method needs to track opened archives when the time comes to eject a disc
	
	// if there is no current edition, throw a tantrum
	if (!currentEdition)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Riven X tried to load an archive without having made an edition current first." userInfo:nil];
	
	// first look in the local data store
	if (_localDataStore) {
		archivePath = [_localDataStore stringByAppendingPathComponent:filename];
		if (BZFSFileExists(archivePath)) {
			archive = [[[MHKArchive alloc] initWithPath:archivePath error:error] autorelease];
			if (!archive)
				return nil;
			else
				return archive;
		}
	}
	
	// then look in the edition user data base
	archivePath = [[currentEdition valueForKey:@"userDataBase"] stringByAppendingPathComponent:filename];
	if (BZFSFileExists(archivePath)) {
		archive = [[[MHKArchive alloc] initWithPath:archivePath error:error] autorelease];
		if (!archive)
			return nil;
		else
			return archive;
	}
	
	// then look on the proper optical media
	NSNumber* discIndex = [currentEdition valueForKeyPath:[NSString stringWithFormat:@"stackDescriptors.%@.Disc", stackID]];
	NSString* disc = [[currentEdition valueForKey:@"discs"] objectAtIndex:(discIndex) ? [discIndex unsignedIntValue] : 0];
	NSString* mountPath = [self mountPathForDisc:disc];
	
	// FIXME: need to setup waiting for the disc
	if (!mountPath) {
		RXOLog2(kRXLoggingEngine, kRXLoggingLevelMessage, @"[WARNING] waiting for discs is not implemented yet, please do full installs or put the proper disc before choosing an edition");
		ReturnValueWithError(nil, 
			RXErrorDomain, kRXErrArchiveUnavailable,
			([NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"The archive file \"%@\" is unavailable on the hard drive or any mounted disc.", filename] forKey:NSLocalizedDescriptionKey]),
			error);
	}
	
	// get the directory for the requested type of archive
	NSString* directory = [[currentEdition valueForKey:@"directories"] objectForKey:dirKey];
	if (!directory)
		ReturnValueWithError(nil,
			RXErrorDomain, kRXErrArchiveUnavailable,
			([NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"The archive file \"%@\" is unavailable on the hard drive or any mounted disc.", filename] forKey:NSLocalizedDescriptionKey]),
			error);
	
	// compute the final on-disc archive path
	archivePath = [[mountPath stringByAppendingPathComponent:directory] stringByAppendingPathComponent:filename];
	if (BZFSFileExists(archivePath)) {
		archive = [[[MHKArchive alloc] initWithPath:archivePath error:error] autorelease];
		if (!archive)
			return nil;
		else
			return archive;
	}
	
	ReturnValueWithError(nil, 
		RXErrorDomain, kRXErrArchiveUnavailable,
		([NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"The archive file \"%@\" is unavailable on the hard drive or any mounted disc.", filename] forKey:NSLocalizedDescriptionKey]),
		error);
}

- (MHKArchive*)dataArchiveWithFilename:(NSString*)filename stackID:(NSString*)stackID error:(NSError**)error {
	if ([stackID isEqualToString:@"aspit"])
		return [self _archiveWithFilename:filename directoryKey:@"All" stackID:stackID error:error];
	return [self _archiveWithFilename:filename directoryKey:@"Data" stackID:stackID error:error];
}

- (MHKArchive*)soundArchiveWithFilename:(NSString*)filename stackID:(NSString*)stackID error:(NSError**)error {
	return [self _archiveWithFilename:filename directoryKey:@"Sound" stackID:stackID error:error];
}

@end
