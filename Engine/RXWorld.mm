//
//  RXWorld.mm
//  rivenx
//
//  Created by Jean-Francois Roy on 25/08/2005.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import <mach/task.h>
#import <mach/thread_act.h>
#import <mach/thread_policy.h>

#import <sys/param.h>
#import <sys/mount.h>

#import "Base/RXThreadUtilities.h"
#import "Base/RXTiming.h"
#import "Base/RXLogCenter.h"

#import "Engine/RXWorld.h"
#import "Engine/RXCursors.h"

#import "Utilities/BZFSUtilities.h"

#import "Rendering/Audio/RXAudioRenderer.h"

#import "States/RXCardState.h"


NSObject <RXWorldProtocol>* g_world = nil;

@interface RXWorld (RXWorldRendering)
- (void)_initializeRendering;
- (void)_toggleFullscreenLegacyPath;
@end

@implementation RXWorld

// disable automatic KVC
+ (BOOL)accessInstanceVariablesDirectly
{
    return NO;
}

+ (RXWorld*)sharedWorld
{
    // WARNING: the first call to this method is not thread safe
    if (g_world == nil)
        g_world = [RXWorld new];
    return (RXWorld*)g_world;
}

- (void)_initEngineVariables
{
    NSError* error = nil;
    NSData* default_vars_data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"EngineVariables" ofType:@"plist"] options:0 error:&error];
    if (!default_vars_data)
        @throw [NSException exceptionWithName:@"RXMissingDefaultEngineVariablesException"
                                       reason:@"Unable to find EngineVariables.plist."
                                     userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
    
    NSString* error_str = nil;
    _engineVariables = [[NSPropertyListSerialization propertyListFromData:default_vars_data
                                                         mutabilityOption:NSPropertyListMutableContainers
                                                                   format:NULL
                                                         errorDescription:&error_str] retain];
    if (!_engineVariables)
        @throw [NSException exceptionWithName:@"RXInvalidDefaultEngineVariablesException"
                                       reason:@"Unable to load the default engine variables."
                                     userInfo:[NSDictionary dictionaryWithObject:error_str forKey:@"RXErrorString"]];
    [error_str release];
    
    NSDictionary* user_vars = [[NSUserDefaults standardUserDefaults] objectForKey:@"EngineVariables"];
    if (user_vars)
    {
        NSEnumerator* keypaths = [user_vars keyEnumerator];
        NSString* keypath;
        while ((keypath = [keypaths nextObject]))
            [_engineVariables setValue:[user_vars objectForKey:keypath] forKeyPath:keypath];
    }
    else
        [[NSUserDefaults standardUserDefaults] setValue:[NSMutableDictionary dictionary] forKey:@"EngineVariables"];
}

- (void)_initEngineLocations
{
    NSError* error;
    
    [_worldBase release];
    [_worldCacheBase release];
    
    // world base is the parent directory of the application bundle
    _worldBase = (NSURL*)CFURLCreateWithFileSystemPath(NULL, (CFStringRef)[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent], kCFURLPOSIXPathStyle, true);
    
    FSRef cachesFolderRef;
    OSErr os_err = FSFindFolder(kUserDomain, kCachedDataFolderType, kDontCreateFolder, &cachesFolderRef);
    if (os_err != noErr)
    {
        error = [NSError errorWithDomain:NSOSStatusErrorDomain code:os_err userInfo:nil];
        @throw [NSException exceptionWithName:@"RXFilesystemException"
                                       reason:@"Riven X was unable to locate your user's caches folder."
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    }
    
    NSURL* cachesFolderURL = [(NSURL*)CFURLCreateFromFSRef(kCFAllocatorDefault, &cachesFolderRef) autorelease];
    release_assert(cachesFolderURL);
    
    // the world shared base is a bundle-identifier folder inside the ~/Library/Caches
    NSString* cachesDirPath = [[cachesFolderURL path] stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]];
    if (!BZFSDirectoryExists(cachesDirPath))
    {
        BOOL success = BZFSCreateDirectoryExtended(cachesDirPath, @"admin", 0775, &error);
        if (!success)
            @throw [NSException exceptionWithName:@"RXFilesystemException"
                                           reason:@"Riven X was unable to create its caches folder."
                                         userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    }
    _worldCacheBase = (NSURL*)CFURLCreateWithFileSystemPath(NULL, (CFStringRef)cachesDirPath, kCFURLPOSIXPathStyle, true);
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
    if (context == [_engineVariables objectForKey:@"rendering"])
    {
        if ([keyPath isEqualToString:@"volume"])
            reinterpret_cast<RX::AudioRenderer*>(_audioRenderer)->SetGain([[change objectForKey:NSKeyValueChangeNewKey] floatValue]);
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (id)init
{
    self = [super init];
    if (!self)
        return nil;
    
    @try
    {
        _tornDown = NO;
        
        // WARNING: the world has to run on the main thread
        if (!pthread_main_np())
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"initSingleton: MAIN THREAD ONLY" userInfo:nil];
        
        // initialize threading
        RXSetThreadName("main");
        
        // initialize timing
        RXTimingUpdateTimebase();
        
        // initialize logging
        [RXLogCenter sharedLogCenter];
        
        RXOLog2(kRXLoggingEngine, kRXLoggingLevelMessage, @"I am the first and the last, the alpha and the omega, the beginning and the end.");
        RXOLog2(kRXLoggingEngine, kRXLoggingLevelMessage, @"Riven X version %@ (%@)",
            [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
            [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]);
        
        // seed random
        srandom((unsigned)time(NULL));
        
        // initialize the engine variables
        _engineVariablesLock = OS_SPINLOCK_INIT;
        [self _initEngineVariables];
        
        // initialize engine location URLs (the bases)
        [self _initEngineLocations];
        
        // load the shared preferences
        _cachePreferences = [[NSMutableDictionary alloc] initWithContentsOfFile:[[[self worldCacheBase] path] stringByAppendingPathComponent:@"RivenX.plist"]];
        if (!_cachePreferences)
            _cachePreferences = [NSMutableDictionary new];
        
        // apply the WorldBase override preference
        if ([_cachePreferences objectForKey:@"WorldBase"])
        {
            if (BZFSDirectoryExists([_cachePreferences objectForKey:@"WorldBase"]))
            {
                [_worldBase release];
                _worldBase = [[NSURL fileURLWithPath:[_cachePreferences objectForKey:@"WorldBase"]] retain];
            }
            else
            {
                [self setWorldBaseOverride:nil];
            }
        }
        
        // the active stacks dictionary maps stack keys (e.g. aspit, etc.) to RXStack objects
        _activeStacks = [NSMutableDictionary new];
        
        // load Extras.plist
        _extrasDescriptor = [[NSDictionary alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Extras" ofType:@"plist"]];
        if (!_extrasDescriptor)
            @throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Failed to load Extras.plist." userInfo:nil];
        
        /*  Notes on Extras.MHK
            *
            *  The marble and bottom book / journal icons are described in Extras.plist (Books and Marbles keys)
            *
            *  The credits are 302 and 303 for the standalones, then 304 to 320 for the scrolling composite
        */
        
        // load Stacks.plist
        _stackDescriptors = [[NSDictionary alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Stacks" ofType:@"plist"]];
        if (!_stackDescriptors)
            @throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Failed to load Stacks.plist." userInfo:nil];
        
        // load cursors metadata
        NSDictionary* cursorMetadata = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Cursors" ofType:@"plist"]];
        if (!cursorMetadata)
            @throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Failed to load Cursors.plist." userInfo:nil];
        
        // load cursors
        _cursors = NSCreateMapTable(NSIntegerMapKeyCallBacks, NSObjectMapValueCallBacks, 20);
        
        [cursorMetadata enumerateKeysAndObjectsUsingBlock:^(NSString* cursorKey, NSString* cursorHotspotPointString, BOOL* stop)
        {
            NSPoint cursorHotspot = NSPointFromString(cursorHotspotPointString);
            NSImage* cursorImage = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:cursorKey ofType:@"png" inDirectory:@"cursors"]];
            if (!cursorImage)
                @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                               reason:[NSString stringWithFormat:@"Unable to find cursor %@.", cursorKey]
                                             userInfo:nil];
            
            NSCursor* cursor = [[NSCursor alloc] initWithImage:cursorImage hotSpot:cursorHotspot];
            uintptr_t key = [cursorKey intValue];
            NSMapInsert(_cursors, (const void*)key, (const void*)cursor);
            
            [cursor release];
            [cursorImage release];
        }];
                
        // the semaphore will be signaled when a thread has setup inter-thread messaging
        kern_return_t kerr = semaphore_create(mach_task_self(), &_threadInitSemaphore, SYNC_POLICY_FIFO, 0);
        if (kerr != 0)
            @throw [NSException exceptionWithName:NSMachErrorDomain reason:@"Could not allocate stack thread init semaphore." userInfo:nil];
        
        // start threads
        [NSThread detachNewThreadSelector:@selector(_RXScriptThreadEntry:) toTarget:self withObject:nil];
        
        // wait for each thread to be running (this needs to be called the same number of times as the number of threads)
        semaphore_wait(_threadInitSemaphore);
        
        // register for card changed notifications
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_activeCardDidChange:) name:@"RXActiveCardDidChange" object:nil];
    }
    @catch (NSException* e)
    {
        [[NSApp delegate] performSelectorOnMainThread:@selector(notifyUserOfFatalException:) withObject:e waitUntilDone:NO];
        [self release];
        self = nil;
    }
    
    // set the global to ourselves
    g_world = self;
    
    return self;
}

- (void)initializeRendering
{
    if (_renderingInitialized)
        return;
    
    @try
    {
        // initialize rendering
        [self _initializeRendering];
        
        _renderingInitialized = YES;
    }
    @catch (NSException* e)
    {
        [[NSApp delegate] performSelectorOnMainThread:@selector(notifyUserOfFatalException:) withObject:e waitUntilDone:NO];
    }
}

- (void)tearDown
{
    // WARNING: this method can only run on the main thread
    if (!pthread_main_np())
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_tearDown: MAIN THREAD ONLY" userInfo:nil];
    
#if defined(DEBUG)
    RXOLog(@"tearing down");
#endif
    _tornDown = YES;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    
    if (g_worldView)
        [[g_worldView window] setDelegate:nil];
    [_cardRenderer release], _cardRenderer = nil;
    [g_worldView tearDown];
    
    if (_audioRenderer)
    {
        reinterpret_cast<RX::AudioRenderer*>(_audioRenderer)->Stop();
        delete reinterpret_cast<RX::AudioRenderer*>(_audioRenderer);
        _audioRenderer = 0;
    }
    
    if (_scriptThread)
        [self performSelector:@selector(_stopThreadRunloop) inThread:_scriptThread];
    
    semaphore_destroy(mach_task_self(), _threadInitSemaphore);
    
    if (_cursors)
        NSFreeMapTable(_cursors);
    _cursors = nil;
    
    [_extrasDescriptor release], _extrasDescriptor = nil;
    [_gameState release], _gameState = nil;
    [_worldBase release], _worldBase = nil;
    [_worldCacheBase release], _worldCacheBase = nil;
    [_engineVariables release], _engineVariables = nil;
    [_activeStacks release], _activeStacks = nil;
    [_cachePreferences release], _cachePreferences = nil;
}

#pragma mark -

- (void)_RXScriptThreadEntry:(id)object
{
    // reference to the thread
    _scriptThread = [NSThread currentThread];
    
    // run the thread
    RXThreadRunLoopRun(_threadInitSemaphore, "script");
}

- (void)_stopThreadRunloop
{
    CFRunLoopStop(CFRunLoopGetCurrent());
}

- (NSThread*)scriptThread
{
    return _scriptThread;
}

#pragma mark -

- (NSURL*)worldBase
{
    return _worldBase;
}

- (NSURL*)worldCacheBase
{
    return _worldCacheBase;
}

- (void)_writeCachePreferences
{
    [_cachePreferences writeToFile:[[[self worldCacheBase] path] stringByAppendingPathComponent:@"RivenX.plist"] atomically:NO];
}

- (BOOL)isInstalled
{
    return [[_cachePreferences objectForKey:@"IsInstalled2"] boolValue];
}

- (void)setIsInstalled:(BOOL)flag
{
    [_cachePreferences setObject:[NSNumber numberWithBool:flag] forKey:@"IsInstalled2"];
    [self _writeCachePreferences];
}

- (void)setWorldBaseOverride:(NSString*)path
{
    if (path)
    {
        [_worldBase release];
        _worldBase = [[NSURL fileURLWithPath:path] retain];
        
        [_cachePreferences setObject:path forKey:@"WorldBase"];
    }
    else
    {
        [self _initEngineLocations];
        [_cachePreferences removeObjectForKey:@"WorldBase"];
    }
    
    [self _writeCachePreferences];
}

#pragma mark -

- (NSDictionary*)extraBitmapsDescriptor
{
    return _extrasDescriptor;
}

- (NSCursor*)defaultCursor
{
    return [self cursorForID:RX_CURSOR_FORWARD];
}

- (NSCursor*)openHandCursor
{
    return [self cursorForID:RX_CURSOR_OPEN_HAND];
}

- (NSCursor*)invisibleCursor
{
    return [self cursorForID:RX_CURSOR_INVISIBLE];
}

- (NSCursor*)cursorForID:(uint16_t)ID
{
    uintptr_t key = ID;
    return (NSCursor*)NSMapGet(_cursors, (const void*)key);
}

#pragma mark -

- (NSView <RXWorldViewProtocol> *)worldView
{
    return _worldView;
}

- (void*)audioRenderer
{
    return _audioRenderer;
}

- (RXRenderState*)cardRenderer
{
    return _cardRenderer;
}

- (BOOL)fullscreen
{
    return _fullscreen;
}

- (void)toggleFullscreenLegacyPath
{
    [self _toggleFullscreenLegacyPath];
}

#pragma mark -

- (RXGameState*)gameState
{
    return _gameState;
}

- (void)_activeCardDidChange:(NSNotification*)notification
{
    // NOTE: WILL RUN ON THE MAIN THREAD
    
    // if we have a new game state to load and we just cleared the active card, do the swap
    if (![notification object] && _gameStateToLoad)
    {
        // swap the game state
        [_gameState release];
        _gameState = _gameStateToLoad;
        _gameStateToLoad = nil;
        
        // post a notification informing everyone that a new game state has been loaded
        [[NSNotificationCenter defaultCenter] postNotificationName:@"RXGameStateLoadedNotification" object:_gameState userInfo:nil];
        
        // set the active card to that of the new game state
        // NOTE: some cards except hotspot handling to be disabled when they open because
        //       almost always they are opening as a result of a mouse down action; to work
        //       around this fact, disable hotspot handling right now and queue up the enable
        //       hotspot handling method on the script thread after changing the active card
        RXSimpleCardDescriptor* scd = [_gameState currentCard];
        
        [(RXCardState*)_cardRenderer disableHotspotHandling];
        [(RXCardState*)_cardRenderer setActiveCardWithStack:scd->stackKey ID:scd->cardID waitUntilDone:NO];
        [(RXCardState*)_cardRenderer performSelector:@selector(enableHotspotHandling) withObject:nil inThread:_scriptThread waitUntilDone:NO];
    }
}

- (void)_loadGameFadeInFinished
{
    [(RXCardState*)_cardRenderer showMouseCursor];
}

- (void)_loadGameFadeOutFinished
{
    [g_worldView fadeInWithDuration:0.5 completionDelegate:self selector:@selector(_loadGameFadeInFinished)];
    [(RXCardState*)_cardRenderer clearActiveCardWaitingUntilDone:NO];
}

- (void)loadGameState:(RXGameState*)gameState
{
    _gameStateToLoad = [gameState retain];
    
    // load the stack of the game state's current card to make sure we can actually run and load that save
    if (![self loadStackWithKey:[[_gameStateToLoad currentCard] stackKey]])
        return;
    
    // ensure that rendering has been initialized, since we require the card renderer to load a game state
    [self initializeRendering];
    
    // fade out over 0.5 seconds and load the new game when the fade completes
    [(RXCardState*)_cardRenderer hideMouseCursor];
    [g_worldView fadeOutWithDuration:0.5 completionDelegate:self selector:@selector(_loadGameFadeOutFinished)];
}

#pragma mark -
#pragma mark stack management

- (NSDictionary*)stackDescriptorForKey:(NSString*)stackKey
{
    return [_stackDescriptors objectForKey:stackKey];
}

- (RXStack*)activeStackWithKey:(NSString*)stackKey
{
    return [_activeStacks objectForKey:stackKey];
}

- (void)_postStackLoadedNotification:(NSString*)stackKey
{
    // WARNING: MUST RUN ON THE MAIN THREAD
    if (!pthread_main_np())
    {
        [self performSelectorOnMainThread:@selector(_postStackLoadedNotification:) withObject:stackKey waitUntilDone:NO];
        return;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RXStackDidLoadNotification" object:stackKey userInfo:nil];
}

- (RXStack*)loadStackWithKey:(NSString*)stackKey
{
    RXStack* stack = [self activeStackWithKey:stackKey];
    if (stack)
        return stack;
    
    // initialize the stack
    NSError* error;
    stack = [[RXStack alloc] initWithKey:stackKey error:&error];
    if (!stack)
    {
        error = [RXError errorWithDomain:RXErrorDomain code:kRXErrFailedToInitializeStack userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
            [error localizedDescription], NSLocalizedDescriptionKey,
            NSLocalizedString(@"UNINSTALL_RECOVERY", nil), NSLocalizedRecoverySuggestionErrorKey,
            [NSArray arrayWithObjects:NSLocalizedString(@"QUIT", @"quit"), NSLocalizedString(@"UNINSTALL", @"quit"), nil], NSLocalizedRecoveryOptionsErrorKey,
            [NSApp delegate], NSRecoveryAttempterErrorKey,
            error, NSUnderlyingErrorKey,
            nil]];
        [NSApp performSelectorOnMainThread:@selector(presentError:) withObject:error waitUntilDone:NO];
        return nil;
    }
    
    // store the new stack in the active stacks dictionary
    [_activeStacks setObject:stack forKey:stackKey];
    
    // give up ownership of the new stack
    [stack release];
    
    // post the stack loaded notification on the main thread
    [self _postStackLoadedNotification:stackKey];
    
    // return the stack
    return stack;
}

#pragma mark -

- (void)_dumpEngineVariables
{
    OSSpinLockLock(&_engineVariablesLock);
    RXOLog(@"dumping engine variables\n%@", _engineVariables);
    OSSpinLockUnlock(&_engineVariablesLock);
}

- (id)valueForEngineVariable:(NSString*)path
{
    OSSpinLockLock(&_engineVariablesLock);
    id value = [_engineVariables valueForKeyPath:path];
    OSSpinLockUnlock(&_engineVariablesLock);
    return value;
}

- (void)setValue:(id)value forEngineVariable:(NSString*)path
{
    OSSpinLockLock(&_engineVariablesLock);
    [_engineVariables setValue:value forKeyPath:path];
    [[NSUserDefaults standardUserDefaults] setObject:_engineVariables forKey:@"EngineVariables"];
    OSSpinLockUnlock(&_engineVariablesLock);
}

@end
