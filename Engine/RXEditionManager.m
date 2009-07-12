//
//  RXEditionManager.m
//  rivenx
//
//  Created by Jean-Francois Roy on 02/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Carbon/Carbon.h>

#import "Engine/RXEditionManager.h"
#import "Engine/RXWorld.h"

#import "Utilities/BZFSUtilities.h"
#import "Utilities/GTMObjectSingleton.h"


@implementation RXEditionManager

GTMOBJECT_SINGLETON_BOILERPLATE(RXEditionManager, sharedEditionManager)

- (void)_scanMountPath:(NSString*)mp {
    NSAutoreleasePool* p = [NSAutoreleasePool new];
    
#if defined(DEBUG)
    RXOLog(@"scanning %@", mp);
#endif

    // the goal of this method is to check if at least one edition is interested in the new mount path
    NSEnumerator* e = [editions objectEnumerator];
    RXEdition* ed;
    while ((ed = [e nextObject])) {
        if ([ed isValidMountPath:mp]) {
            if (![_valid_mount_paths containsObject:mp]) {
                OSSpinLockLock(&_valid_mount_paths_lock);
                [_valid_mount_paths addObject:mp];
                OSSpinLockUnlock(&_valid_mount_paths_lock);
                
                [self performSelectorOnMainThread:@selector(_handleNewValidMountPath:) withObject:mp waitUntilDone:NO];
            }
            return;
        }
    }
    
    [p release];
}

- (void)_handleNewValidMountPath:(NSString*)path {
    // were we waiting for this disc?
    if (_waiting_disc_name) {
        if ([[path lastPathComponent] isEqualToString:_waiting_disc_name]) {
            [_waiting_disc_name release];
            _waiting_disc_name = nil;
        } else
            [NSThread detachNewThreadSelector:@selector(ejectMountPath:) toTarget:self withObject:path];
    }
}

- (void)_removableMediaMounted:(NSNotification*)notification {
    NSString* path = [[notification userInfo] objectForKey:@"NSDevicePath"];
    
    // scan the new mount path in a thread since RXEdition -isValidMountPath can take a long time
    [NSThread detachNewThreadSelector:@selector(_scanMountPath:) toTarget:self withObject:path];
}

- (void)_removableMediaUnmounted:(NSNotification*)notification {
    NSString* path = [[notification userInfo] objectForKey:@"NSDevicePath"];
#if defined(DEBUG)
    RXOLog(@"removable media mounted at %@ is gone", path);
#endif
    
    OSSpinLockLock(&_valid_mount_paths_lock);
    [_valid_mount_paths removeObject:path];
    OSSpinLockUnlock(&_valid_mount_paths_lock);
}

- (void)_initialMediaScan {
    NSAutoreleasePool* p = [NSAutoreleasePool new];
    
    NSArray* mounted_media = [[NSWorkspace sharedWorkspace] mountedRemovableMedia];
    
    // search for Riven data stores
    NSEnumerator* media_enum = [mounted_media objectEnumerator];
    NSString* path;
    while ((path = [media_enum nextObject]))
        [self _scanMountPath:path];
    
    [p release];
}

#pragma mark -

- (BOOL)_writeSettings {
    NSData* settings_data = [NSPropertyListSerialization dataFromPropertyList:_settings
                                                                       format:NSPropertyListBinaryFormat_v1_0
                                                             errorDescription:NULL];
    if (!settings_data)
        return NO;
    
    NSString* settings_path = [[[[RXWorld sharedWorld] worldUserBase] path] stringByAppendingPathComponent:@"Edtion Manager.plist"];
    return [settings_data writeToFile:settings_path options:NSAtomicWrite error:NULL];
}

#pragma mark -

- (id)init  {
    self = [super init];
    if (!self)
        return nil;
    
    editions = [NSMutableDictionary new];
    edition_proxies = [NSMutableArray new];
    
    active_stacks = [NSMutableDictionary new];
    
    _valid_mount_paths_lock = OS_SPINLOCK_INIT;
    _valid_mount_paths = [NSMutableArray new];
    _waiting_disc_name = nil;
    
    // find the Editions directory
    NSString* editions_directory = [[NSBundle mainBundle] pathForResource:@"Editions" ofType:nil];
    if (!editions_directory)
        @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                       reason:@"Riven X could not find the Editions bundle resource directory."
                                     userInfo:nil];
    
    // cache the path to the Patches directory
    _patches_directory = [[editions_directory stringByAppendingPathComponent:@"Patches"] retain];
    
    // get its content
    NSFileManager* fm = [NSFileManager defaultManager];
    NSArray* edition_plists;
    NSError* error = nil;
    if ([fm respondsToSelector:@selector(contentsOfDirectoryAtPath:error:)])
        edition_plists = [fm contentsOfDirectoryAtPath:editions_directory error:&error];
    else
        edition_plists = [fm directoryContentsAtPath:editions_directory];
    if (!edition_plists)
        @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                       reason:@"Riven X could not iterate the Editions bundle resource directory."
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    
    // iterate over its content
    NSEnumerator* e = [edition_plists objectEnumerator];
    NSString* item;
    while ((item = [e nextObject])) {
        // is it a plist?
        if (![[item pathExtension] isEqualToString:@"plist"])
            continue;
        
        // cache the full path
        NSString* plist_path = [editions_directory stringByAppendingPathComponent:item];
        
        // try to allocate an edition object
        RXEdition* ed = [[RXEdition alloc] initWithDescriptor:[NSDictionary dictionaryWithContentsOfFile:plist_path]];
        if (!ed)
            RXOLog(@"failed to load edition %@", item);
        else {
            [editions setObject:ed forKey:[ed valueForKey:@"key"]];
            [edition_proxies addObject:[ed proxy]];
        }
        [ed release];
    }
    
    // get the location of the local data store
    _local_data_store = [[[[[RXWorld sharedWorld] worldBase] path] stringByAppendingPathComponent:@"Data"] retain];
    
#if defined(DEBUG)
    if (!BZFSDirectoryExists(_local_data_store)) {
        [_local_data_store release];
        _local_data_store = [[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"Data"] retain];
    }
#endif
    
    // check if the local data store exists (it is not required)
    if (!BZFSDirectoryExists(_local_data_store)) {
        [_local_data_store release];
        _local_data_store = nil;
#if defined(DEBUG)
        RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"no local data store could be found");
#endif
    }
    
    // do an initial scan of mounted media on a background thread so we don't block the UI
    [NSThread detachNewThreadSelector:@selector(_initialMediaScan) toTarget:self withObject:nil];
    
    // register for removable media notifications
    NSNotificationCenter* ws_notification_center = [[NSWorkspace sharedWorkspace] notificationCenter];
    [ws_notification_center addObserver:self selector:@selector(_removableMediaMounted:) name:NSWorkspaceDidMountNotification object:nil];
    [ws_notification_center addObserver:self selector:@selector(_removableMediaUnmounted:) name:NSWorkspaceDidUnmountNotification object:nil];
    
    // load edition manager settings
    NSString* settings_path = [[[[RXWorld sharedWorld] worldUserBase] path] stringByAppendingPathComponent:@"Edtion Manager.plist"];
    if (BZFSFileExists(settings_path)) {
        NSData* settings_data = [NSData dataWithContentsOfFile:settings_path options:0 error:&error];
        if (settings_data == nil)
            @throw [NSException exceptionWithName:@"RXIOException"
                                           reason:@"Riven X could not load the existing edition manager settings."
                                         userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
        
        NSString* error_string = nil;
        _settings = [[NSPropertyListSerialization propertyListFromData:settings_data
                                                      mutabilityOption:NSPropertyListMutableContainers
                                                                format:NULL errorDescription:&error_string] retain];
        if (_settings == nil)
            @throw [NSException exceptionWithName:@"RXIOException"
                                           reason:@"Riven X could not load the existing edition manager settings."
                                         userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error_string, @"RXErrorString", nil]];
        [error_string release];
    } else
        _settings = [NSMutableDictionary new];
    
    // if we have an edition selection saved in the settings, try to use it; otherwise, display the edition manager; 
    // we use a performSelector because the world is not done initializing when the edition manager is initialized
    // and we must defer the edition changed notification until the next run loop cycle
    RXEdition* default_edition = [self defaultEdition];
    
    BOOL option_pressed = ((GetCurrentKeyModifiers() & (optionKey | rightOptionKey)) != 0) ? YES : NO;
    if (default_edition && !option_pressed)
        [self performSelectorOnMainThread:@selector(_makeEditionChoiceMemoryCurrent) withObject:nil waitUntilDone:NO];
    else
        [self showEditionManagerWindow];
    
    return self;
}

- (void)tearDown {
    if (_torn_down)
        return;
    _torn_down = YES;
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    
    [_window_controller close];
    [_window_controller release];
    
    [_valid_mount_paths release];
    [_waiting_disc_name release];
    
    [_local_data_store release];
}

- (void)dealloc {
    [self tearDown];
    
    [_patches_directory release];
    
    [editions release];
    [edition_proxies release];
    
    [active_stacks release];
    
    [super dealloc];
}

- (NSArray*)editionProxies {
    return [[edition_proxies retain] autorelease];
}

- (RXEdition*)editionForKey:(NSString*)editionKey {
    return [[[editions objectForKey:editionKey] retain] autorelease];
}

- (RXEdition*)currentEdition {
    return [[current_edition retain] autorelease];
}

- (void)showEditionManagerWindow {
    if (!_window_controller)
        _window_controller = [[RXEditionManagerWindowController alloc] initWithWindowNibName:@"EditionManager"];

    [[_window_controller window] center];
    [_window_controller showWindow:self];
}

- (RXEdition*)defaultEdition {
    return [editions objectForKey:[_settings objectForKey:@"RXEditionChoiceMemory"]];
}

- (void)setDefaultEdition:(RXEdition*)edition {
    if (edition)
        [_settings setObject:[edition valueForKey:@"key"] forKey:@"RXEditionChoiceMemory"];
    else
        [_settings removeObjectForKey:@"RXEditionChoiceMemory"];
    [self _writeSettings];
}

- (void)resetDefaultEdition {
    [self setDefaultEdition:nil];
}

- (BOOL)makeEditionCurrent:(RXEdition*)edition rememberChoice:(BOOL)remember error:(NSError**)error {
    if ([edition isEqual:current_edition]) {
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
    
    // unload all stacks since they are associated to the current edition
    [active_stacks removeAllObjects];
    
    // change the current edition ivar and post the current edition changed notification
    current_edition = edition;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RXCurrentEditionChangedNotification" object:edition];
    
#if defined(DEBUG)
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"made %@ the current edition", edition);
#endif
    return YES;
}

- (void)_makeEditionChoiceMemoryCurrent {
    // NOTE: WILL RUN ON THE MAIN THREAD
    NSError* error;
    
    RXEdition* default_edition = [self defaultEdition];
    if (!default_edition)
        [self showEditionManagerWindow];
    
    if (![self makeEditionCurrent:default_edition rememberChoice:YES error:&error]) {
        if ([error code] == kRXErrEditionCantBecomeCurrent && [error domain] == RXErrorDomain) {
            [self resetDefaultEdition];
            
            error = [NSError errorWithDomain:[error domain] code:[error code] userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                [NSString stringWithFormat:@"Riven X cannot make \"%@\" the current edition because it is not installed.", [default_edition valueForKey:@"name"]], NSLocalizedDescriptionKey,
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
    // do this on a background thread because it can take a while
    OSSpinLockLock(&_valid_mount_paths_lock);
    NSString* last_valid_mount_path = [_valid_mount_paths lastObject];
    OSSpinLockUnlock(&_valid_mount_paths_lock);
    if (last_valid_mount_path)
        [NSThread detachNewThreadSelector:@selector(ejectMountPath:) toTarget:self withObject:last_valid_mount_path];
    
    _waiting_disc_name = [disc retain];
    while (_waiting_disc_name) {
        if (session) {
            if ([NSApp runModalSession:session] != NSRunContinuesResponse) {
                [_waiting_disc_name release];
                _waiting_disc_name = nil;
            }
        }
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    }
}

- (NSString*)mountPathForDisc:(NSString*)disc {
    return [self mountPathForDisc:disc waitingInModalSession:NULL];
}

- (NSString*)mountPathForDisc:(NSString*)disc waitingInModalSession:(NSModalSession)session {
    OSSpinLockLock(&_valid_mount_paths_lock);
    NSEnumerator* disc_enum = [[NSArray arrayWithArray:_valid_mount_paths] objectEnumerator];
    OSSpinLockUnlock(&_valid_mount_paths_lock);
    
    NSString* mount;
    while ((mount = [disc_enum nextObject])) {
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
    NSAutoreleasePool* p = [NSAutoreleasePool new];
    
    // don't wait for the unmount to occur to remove the disc from the known valid mount paths
    OSSpinLockLock(&_valid_mount_paths_lock);
    [_valid_mount_paths removeObject:mountPath];
    OSSpinLockUnlock(&_valid_mount_paths_lock);
    
    // don't ask questions, someone doesn't like it
    [[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtPath:mountPath];
    
    [p release];
}

- (RXSimpleCardDescriptor*)lookupCardWithKey:(NSString*)lookup_key {
    return [[current_edition valueForKey:@"cardLUT"] objectForKey:lookup_key];
}

- (uint16_t)lookupBitmapWithKey:(NSString*)lookup_key {
    return [[[current_edition valueForKey:@"bitmapLUT"] objectForKey:lookup_key] unsignedShortValue];
}

- (uint16_t)lookupSoundWithKey:(NSString*)lookup_key {
    return [[[current_edition valueForKey:@"soundLUT"] objectForKey:lookup_key] unsignedShortValue];
}

- (MHKArchive*)_archiveWithFilename:(NSString*)filename directoryKey:(NSString*)dirKey stackKey:(NSString*)stackKey error:(NSError**)error {
    NSString* archive_path;
    MHKArchive* archive = nil;
        
    // if there is no current edition, throw a tantrum
    if (!current_edition)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Riven X tried to load an archive without having made an edition current first."
                                     userInfo:nil];
    
    // first look in the local data store
    if (_local_data_store) {
        archive_path = [_local_data_store stringByAppendingPathComponent:filename];
        if (BZFSFileExists(archive_path)) {
            archive = [[[MHKArchive alloc] initWithPath:archive_path error:error] autorelease];
            if (!archive)
                return nil;
            else
                return archive;
        }
    }
    
    // then look in the edition user data base
    archive_path = [[current_edition valueForKey:@"userDataBase"] stringByAppendingPathComponent:filename];
    if (BZFSFileExists(archive_path)) {
        archive = [[[MHKArchive alloc] initWithPath:archive_path error:error] autorelease];
        if (!archive)
            return nil;
        else
            return archive;
    }
    
    // then look on the proper optical media
    NSNumber* disc_index = [current_edition valueForKeyPath:[NSString stringWithFormat:@"stackDescriptors.%@.Disc", stackKey]];
    NSString* disc = [[current_edition valueForKey:@"discs"] objectAtIndex:(disc_index) ? [disc_index unsignedIntValue] : 0];
    NSString* mount_path = [self mountPathForDisc:disc];
    
    // FIXME: need to setup waiting for the disc
    if (!mount_path) {
        RXOLog2(kRXLoggingEngine, kRXLoggingLevelMessage, @"[WARNING] waiting for discs is not implemented yet, please do full installs or put the proper disc before choosing an edition");
        ReturnValueWithError(nil, 
            RXErrorDomain, kRXErrArchiveUnavailable,
            ([NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"The Riven data file \"%@\" is unavailable.", filename] forKey:NSLocalizedDescriptionKey]),
            error);
    }
    
    // get the directory for the requested type of archive
    NSString* directory = [[current_edition valueForKey:@"directories"] objectForKey:dirKey];
    if (!directory)
        ReturnValueWithError(nil,
            RXErrorDomain, kRXErrArchiveUnavailable,
            ([NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"The Riven data file \"%@\" is unavailable.", filename] forKey:NSLocalizedDescriptionKey]),
            error);
    
    // compute the final on-disc archive path
    archive_path = [[mount_path stringByAppendingPathComponent:directory] stringByAppendingPathComponent:filename];
    if (BZFSFileExists(archive_path)) {
        archive = [[[MHKArchive alloc] initWithPath:archive_path error:error] autorelease];
        if (!archive)
            return nil;
        else
            return archive;
    }
    
    ReturnValueWithError(nil, 
        RXErrorDomain, kRXErrArchiveUnavailable,
        ([NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"The Riven data file \"%@\" is unavailable.", filename] forKey:NSLocalizedDescriptionKey]),
        error);
}

- (NSArray*)dataPatchArchivesForStackKey:(NSString*)stackKey error:(NSError**)error {
    // if there is no current edition, throw a tantrum
    if (!current_edition)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Riven X tried to load a patch archive without having made an edition current first."
                                     userInfo:nil];
    
    NSString* edition_patches_directory = [_patches_directory stringByAppendingPathComponent:[current_edition valueForKey:@"key"]];
    NSDictionary* patch_archives = [current_edition valueForKey:@"patchArchives"];
    
    // if the edition has no patch archives, return an empty array
    if (!patch_archives)
        return [NSArray array];
    
    // get the patch archives for the requested stack; if there are none, return an empty array
    NSDictionary* stack_patch_archives = [patch_archives objectForKey:stackKey];
    if (!stack_patch_archives)
        return [NSArray array];
    
    // get the data patch archives; if there are none, return an empty array
    NSArray* data_patch_archives = [stack_patch_archives objectForKey:@"Data Archives"];
    if (!data_patch_archives)
        return [NSArray array];
    
    // load the data archives
    NSMutableArray* data_archives = [NSMutableArray array];
    
    NSEnumerator* archive_enumerator = [data_patch_archives objectEnumerator];
    NSString* archive_name;
    while ((archive_name = [archive_enumerator nextObject])) {
        NSString* archive_path = [edition_patches_directory stringByAppendingPathComponent:archive_name];
        if (!BZFSFileExists(archive_path))
            continue;
        
        MHKArchive* archive = [[MHKArchive alloc] initWithPath:archive_path error:error];
        if (!archive)
            return nil;
        
        [data_archives addObject:archive];
        [archive release];
    }
    
    return data_archives;
}

- (MHKArchive*)dataArchiveWithFilename:(NSString*)filename stackKey:(NSString*)stackKey error:(NSError**)error {
    MHKArchive* archive = nil;
    if ([stackKey isEqualToString:@"aspit"])
        archive = [self _archiveWithFilename:filename directoryKey:@"All" stackKey:stackKey error:error];
    if (!archive)
        archive = [self _archiveWithFilename:filename directoryKey:@"Data" stackKey:stackKey error:error];
    return archive;
}

- (MHKArchive*)soundArchiveWithFilename:(NSString*)filename stackKey:(NSString*)stackKey error:(NSError**)error {
    return [self _archiveWithFilename:filename directoryKey:@"Sound" stackKey:stackKey error:error];
}

- (RXStack*)activeStackWithKey:(NSString*)stackKey {
    return [active_stacks objectForKey:stackKey];
}

- (void)_postStackLoadedNotification:(NSString*)stackKey {
    // WARNING: MUST RUN ON THE MAIN THREAD
    if (!pthread_main_np()) {
        [self performSelectorOnMainThread:@selector(_postStackLoadedNotification:) withObject:stackKey waitUntilDone:NO];
        return;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RXStackDidLoadNotification" object:stackKey userInfo:nil];
}

- (RXStack*)loadStackWithKey:(NSString*)stackKey {
    RXStack* stack = [self activeStackWithKey:stackKey];
    if (stack)
        return stack;
    
    NSError* error;
        
    // get the stack descriptor from the current edition
    NSDictionary* stack_descriptor = [[[RXEditionManager sharedEditionManager] currentEdition] valueForKeyPath:[NSString stringWithFormat:@"stackDescriptors.%@", stackKey]];
    if (!stack_descriptor || ![stack_descriptor isKindOfClass:[NSDictionary class]])
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Stack descriptor object is nil or of the wrong type."
                                     userInfo:stack_descriptor];
    
    // initialize the stack
    stack = [[RXStack alloc] initWithStackDescriptor:stack_descriptor key:stackKey error:&error];
    if (!stack) {
        error = [NSError errorWithDomain:[error domain] code:[error code] userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
            [error localizedDescription], NSLocalizedDescriptionKey,
            @"To re-install your Riven edition, relaunch Riven X while holding down the Option key. If you have a Riven DVD edition, you may instead insert your disc and relaunch Riven X.", NSLocalizedRecoverySuggestionErrorKey,
            [NSArray arrayWithObjects:@"Quit", nil], NSLocalizedRecoveryOptionsErrorKey,
            [NSApp delegate], NSRecoveryAttempterErrorKey,
            error, NSUnderlyingErrorKey,
            nil]];
        [NSApp performSelectorOnMainThread:@selector(presentError:) withObject:error waitUntilDone:NO];
        return nil;
    }
        
    // store the new stack in the active stacks dictionary
    [active_stacks setObject:stack forKey:stackKey];
    
    // give up ownership of the new stack
    [stack release];
    
    // post the stack loaded notification on the main thread
    [self _postStackLoadedNotification:stackKey];
    
    // return the stack
    return stack;
}

@end
