//
//	RXWorld.mm
//	rivenx
//
//	Created by Jean-Francois Roy on 25/08/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <mach/task.h>
#import <mach/thread_act.h>
#import <mach/thread_policy.h>

#import <sys/param.h>
#import <sys/mount.h>

#import "RXWorld.h"

#import "GTMObjectSingleton.h"

#import "BZFSUtilities.h"
#import "RXThreadUtilities.h"
#import "RXTiming.h"

#import "RXLogCenter.h"

#import "RXAudioRenderer.h"

#import "RXCardState.h"

NSObject* g_world = nil;


@interface RXWorld (RXWorldPrivate)
- (void)_secondStageInit;
- (void)_removableMediaAvailabilityHasChanged:(NSNotification *)mediaNotidication;
@end

@interface RXWorld (RXWorldRendering)
- (void)_initializeRendering;
- (void)_initializeRenderStates;
@end

@implementation RXWorld

// disable automatic KVC
+ (BOOL)accessInstanceVariablesDirectly {
	return NO;
}

- (void)_initEngineVariables {
	NSError* error = nil;
	NSData* defaultVarData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"EngineVariables" ofType:@"plist"] options:0 error:&error];
	if (!defaultVarData)
		@throw [NSException exceptionWithName:@"RXMissingDefaultEngineVariablesException" reason:@"Unable to find EngineVariables.plist." userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
	
	NSString* errorString = nil;
	_engineVariables = [[NSPropertyListSerialization propertyListFromData:defaultVarData mutabilityOption:NSPropertyListMutableContainers format:NULL errorDescription:&errorString] retain];
	if (!_engineVariables)
		@throw [NSException exceptionWithName:@"RXInvalidDefaultEngineVariablesException" reason:@"Unable to load the default engine variables." userInfo:[NSDictionary dictionaryWithObject:errorString forKey:@"RXErrorString"]];
	[errorString release];
	
#if defined(DEBUG)

#endif
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
    if (context == [_engineVariables objectForKey:@"rendering"]) {
		if ([keyPath isEqualToString:@"volume"])
			reinterpret_cast<RX::AudioRenderer*>(_audioRenderer)->SetGain([[change objectForKey:NSKeyValueChangeNewKey] floatValue]);
	}
	else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


GTMOBJECT_SINGLETON_BOILERPLATE(RXWorld, sharedWorld)

- (id)init {
	self = [super init];
	if (!self)
		return nil;
	
	@try {
		_tornDown = NO;
		
		// WARNING: the world has to run on the main thread
		if (!pthread_main_np())
			@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"initSingleton: MAIN THREAD ONLY" userInfo:nil];
		
		// initialize threading
		RXInitThreading();
		RXSetThreadName(@"Main");
		
		// initialize timing
		RXTimingUpdateTimebase();
		
		// initialize logging
		[RXLogCenter sharedLogCenter];
		
		RXOLog2(kRXLoggingEngine, kRXLoggingLevelMessage, @"I am the first and the last, the alpha and the omega, the beginning and the end.");
		RXOLog2(kRXLoggingEngine, kRXLoggingLevelMessage, @"Riven X version %@ (%@)", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"], [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]);
		
		// set the global to ourselves
		g_world = self;
		
		// second stage initialization
		[self _secondStageInit];
	} @catch (NSException* e) {
		[self notifyUserOfFatalException:e];
		[self release];
		self = nil;
	}
	
	return self;
}

- (void)_secondStageInit {
	NSError* error = nil;
	
	@try {
		// new engine variables
		pthread_mutex_init(&_engineVariablesMutex, NULL);
		[self _initEngineVariables];
		
		// world base is the parent directory of the application bundle
		_worldBase = (NSURL*)CFURLCreateWithFileSystemPath(NULL, (CFStringRef)[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent], kCFURLPOSIXPathStyle, true);
		
		// the world user base is a "Riven X" folder inside the user's Application Support folder
		NSString* userBase = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"Riven X"];
		if (!BZFSDirectoryExists(userBase)) {
			BOOL success = BZFSCreateDirectory(userBase, &error);
			if (!success)
				@throw [NSException exceptionWithName:@"RXFilesystemException" reason:@"Riven X was unable to create its support folder in your Application Support folder." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
		}
		_worldUserBase = (NSURL*)CFURLCreateWithFileSystemPath(NULL, (CFStringRef)userBase, kCFURLPOSIXPathStyle, true);
		
		// register for current edition change notifications
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_currentEditionChanged:) name:@"RXCurrentEditionChangedNotification" object:nil];
		
		// bootstrap the edition manager
		[RXEditionManager sharedEditionManager];
		
		// load Extras.MHK archive
		_extraBitmapsArchive = [[MHKArchive alloc] initWithURL:[NSURL URLWithString:@"Extras.MHK" relativeToURL:_worldBase] error:&error];
		if (!_extraBitmapsArchive)
			_extraBitmapsArchive = [[MHKArchive alloc] initWithURL:[NSURL URLWithString:@"Extras.MHK"] error:&error];
		if (!_extraBitmapsArchive)
			_extraBitmapsArchive = [[MHKArchive alloc] initWithPath:[[NSBundle mainBundle] pathForResource:@"Extras" ofType:@"MHK"] error:&error];
		if (!_extraBitmapsArchive)
			@throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Unable to find Extras.MHK." userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
		
		// load Extras.plist
		_extrasDescriptor = [[NSDictionary alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Extras" ofType:@"plist"]];
		if (!_extrasDescriptor)
			@throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Unable to find Extras.plist." userInfo:nil];
		
		/*	Notes on Extras.MHK
			*
			*  The marble and bottom book / journal icons are described in Extras.plist (Books and Marbles keys)
			*
			*  The credits are 302 and 303 for the standalones, then 304 to 320 for the scrolling composite
		*/
		
		// load cursors metadata
		NSDictionary* cursorMetadata = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Cursors" ofType:@"plist"]];
		if (!cursorMetadata)
			@throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Unable to find Cursors.plist." userInfo:nil];
		
		// load cursors
		_cursors = NSCreateMapTable(NSIntMapKeyCallBacks, NSObjectMapValueCallBacks, 20);
		
		NSEnumerator* cursorEnum = [cursorMetadata keyEnumerator];
		NSString* cursorKey;
		while ((cursorKey = [cursorEnum nextObject])) {
			NSPoint cursorHotspot = NSPointFromString([cursorMetadata objectForKey:cursorKey]);
			NSImage* cursorImage = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:cursorKey ofType:@"png" inDirectory:@"cursors"]];
			if (!cursorImage)
				@throw [NSException exceptionWithName:@"RXMissingResourceException" reason:[NSString stringWithFormat:@"Unable to find cursor %@.", cursorKey] userInfo:nil];
			
			NSCursor* cursor = [[NSCursor alloc] initWithImage:cursorImage hotSpot:cursorHotspot];
			uintptr_t key = [cursorKey intValue];
			NSMapInsert(_cursors, (const void*)key, (const void*)cursor);
			[cursor release];
		}
		
		// things used to load and keep track of stacks
		pthread_rwlock_init(&_stackCreationLock, NULL);
		pthread_rwlock_init(&_activeStacksLock, NULL);
		kern_return_t kerr = semaphore_create(mach_task_self(), &_stackInitSemaphore, SYNC_POLICY_FIFO, 0);
		if (kerr != 0)
			@throw [NSException exceptionWithName:NSMachErrorDomain reason:@"Could not allocate stack init semaphore." userInfo:nil];
		_activeStacks = [[NSMutableDictionary alloc] init];
		
		// the semaphore will be signaled when a thread has setup inter-thread messaging
		kerr = semaphore_create(mach_task_self(), &_threadInitSemaphore, SYNC_POLICY_FIFO, 0);
		if (kerr != 0)
			@throw [NSException exceptionWithName:NSMachErrorDomain reason:@"Could not allocate stack thread init semaphore." userInfo:nil];
	} @catch (NSException* e) {
		[self notifyUserOfFatalException:e];
	}
}

- (void)initializeRendering {
	if (_rendering_initialized)
		return;
	
	@try {
		// initialize rendering
		[self _initializeRendering];
		
		// start threads
		[NSThread detachNewThreadSelector:@selector(_RXStackThreadEntry:) toTarget:self withObject:nil];
		[NSThread detachNewThreadSelector:@selector(_RXScriptThreadEntry:) toTarget:self withObject:nil];
		[NSThread detachNewThreadSelector:@selector(_RXAnimationThreadEntry:) toTarget:self withObject:nil];
		
		semaphore_wait(_threadInitSemaphore);
		semaphore_wait(_threadInitSemaphore);
		semaphore_wait(_threadInitSemaphore);
		
		// initialize the render states
		[self _initializeRenderStates];
		
		_rendering_initialized = YES;
	} @catch (NSException* e) {
		[self notifyUserOfFatalException:e];
	}
}

- (void)_currentEditionChanged:(NSNotification*)notification {
	// create a new game state for the new current edition (if there isn't one yet); if there is, it is assumed to be for the new current edition
	if (!_gameState) {
		_gameState = [[RXGameState alloc] initWithEdition:[[RXEditionManager sharedEditionManager] currentEdition]];
		
		// register for card changed notifications
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_activeCardDidChange:) name:@"RXActiveCardDidChange" object:nil];
	} else
		assert([[_gameState edition] isEqual:[[RXEditionManager sharedEditionManager] currentEdition]]);
	
	// initialize rendering
	[self initializeRendering];
	
	// unload any loaded stacks
	pthread_rwlock_rdlock(&_activeStacksLock);
	[_activeStacks removeAllObjects];
	pthread_rwlock_unlock(&_activeStacksLock);
	
	// load the aspit stack
	[self loadStackWithKey:@"aspit" waitUntilDone:YES];
}

- (void)dealloc {
	[super dealloc];
}

- (void)tearDown {
	// WARNING: this method can only run on the main thread
	if (!pthread_main_np())
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_tearDown: MAIN THREAD ONLY" userInfo:nil];
	
#if defined(DEBUG)
	RXOLog(@"tearing down");
#endif
	// boolean guard for several methods
	_tornDown = YES;
	
	// terminate notifications
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
	
	// cut window delegate messages
	if (RXGetWorldView())
		[[RXGetWorldView() window] setDelegate:nil];
	
	// tear the world view down
	[RXGetWorldView() tearDown];
	
	// stop audio rendering
	if (_audioRenderer)
		reinterpret_cast<RX::AudioRenderer*>(_audioRenderer)->Stop();
	
	// rendering states
	[_cardState release]; _cardState = nil;
	[_creditsState release]; _creditsState = nil;
	[_cyanMovieState release]; _cyanMovieState = nil;
	
	// state compositor
	[_stateCompositor release];
	
	// audio renderer
	delete reinterpret_cast<RX::AudioRenderer*>(_audioRenderer);
	
	// take the stack creation write lock
	pthread_rwlock_wrlock(&_stackCreationLock);
	
	// stacks
	[_activeStacks release]; _activeStacks = nil;
	pthread_rwlock_destroy(&_activeStacksLock);
	semaphore_destroy(mach_task_self(), _stackInitSemaphore);
	
	// give up the stack creation write lock and destroy it
	// NOTE: no other thread will be waiting on this rwlock by now, since _tornDown is YES and tearDown is running in the main thread
	pthread_rwlock_unlock(&_stackCreationLock);
	pthread_rwlock_destroy(&_stackCreationLock);
	
	// terminate threads
	if (_stackThread)
		[self performSelector:@selector(_stopThreadRunloop) inThread:_stackThread];
	if (_scriptThread)
		[self performSelector:@selector(_stopThreadRunloop) inThread:_scriptThread];
	
	// stack thread creation cond / mutex
	semaphore_destroy(mach_task_self(), _threadInitSemaphore);
	
	// extras archive
	[_extrasDescriptor release]; _extrasDescriptor = nil;
	[_extraBitmapsArchive release]; _extraBitmapsArchive = nil;
	
	// cursors
	if (_cursors)
		NSFreeMapTable(_cursors);
	
	// game state
	[_gameState release]; _gameState = nil;
	
	// edition manager
	[[RXEditionManager sharedEditionManager] tearDown];
	
	// world locations
	[_worldBase release]; _worldBase = nil;
	[_worldUserBase release]; _worldUserBase = nil;
	
	// engine variables
	[_engineVariables release]; _engineVariables = nil;
	pthread_mutex_destroy(&_engineVariablesMutex);
}

- (void)notifyUserOfFatalException:(NSException*)e {
	NSAlert* failureAlert = [NSAlert new];
	[failureAlert setMessageText:[e reason]];
	[failureAlert setAlertStyle:NSWarningAlertStyle];
	[failureAlert addButtonWithTitle:NSLocalizedString(@"Quit", @"quit button")];
	
	NSDictionary* userInfo = [e userInfo];
	if (userInfo) {
		if ([userInfo objectForKey:NSUnderlyingErrorKey])
			[failureAlert setInformativeText:[[userInfo objectForKey:NSUnderlyingErrorKey] description]];
		else
			[failureAlert setInformativeText:[e name]];
	} else
		[failureAlert setInformativeText:[e name]];
	
	[failureAlert runModal];
	[failureAlert release];
	
	[NSApp terminate:nil];
}

#pragma mark -

- (void)_RXAnimationThreadEntry:(id)object {
	// reference to the thread
	_animationThread = [NSThread currentThread];
	
	// make the load CGL context default for the stack thread
	CGLSetCurrentContext([_worldView loadContext]);
	
	// run the thread
	RXThreadRunLoopRun(_threadInitSemaphore, @"Animation");
}

- (void)_RXStackThreadEntry:(id)object {
	// reference to the thread
	_stackThread = [NSThread currentThread];
	
	// make the load CGL context default for the stack thread
	CGLSetCurrentContext([_worldView loadContext]);
	
	// run the thread
	RXThreadRunLoopRun(_threadInitSemaphore, @"Stack");
}

- (void)_RXScriptThreadEntry:(id)object {
	// reference to the thread
	_scriptThread = [NSThread currentThread];
	
	// make the load CGL context default for the script thread
	CGLSetCurrentContext([_worldView loadContext]);
	
	// run the thread
	RXThreadRunLoopRun(_threadInitSemaphore, @"Script");
}

- (void)_stopThreadRunloop {
	CFRunLoopStop(CFRunLoopGetCurrent());
}

- (NSThread *)stackThread {
	return _stackThread;
}

- (NSThread*)scriptThread {
	return _scriptThread;
}

- (NSThread*)animationThread {
	return _animationThread;
}

#pragma mark -

- (void)postStackLoadedNotification_:(NSString*)stackKey {
	// WARNING: MUST RUN ON THE MAIN THREAD
	if (!pthread_main_np()) {
		[self performSelectorOnMainThread:@selector(postStackLoadedNotification_:) withObject:stackKey waitUntilDone:NO];
		return;
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:@"RXStackDidLoadNotification" object:stackKey userInfo:nil];
}

- (void)_initializeStackWithInitializationDictionary:(NSDictionary*)stackInitDictionary {
	// take the read (yes, read) lock for stack creation
	// WARNING: there is still a small window for creating a race condition between tearDown and an async create request, but it's tiny
	pthread_rwlock_rdlock(&_stackCreationLock);
	
	NSString* stackKey = [stackInitDictionary objectForKey:@"stackKey"];
	BOOL signal = [[stackInitDictionary objectForKey:@"waitFlag"] boolValue];
	
	@try {
		RXStack* stack = [self activeStackWithKey:stackKey];
		if (stack)
			return;
		
		NSDictionary* stackDescriptor = [[[RXEditionManager sharedEditionManager] currentEdition] valueForKeyPath:[NSString stringWithFormat:@"stackDescriptors.%@", stackKey]];
		if (!stackDescriptor || ![stackDescriptor isKindOfClass:[NSDictionary class]])
			@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Stack descriptor object is nil or of the wrong type." userInfo:stackDescriptor];
		
		stack = [[RXStack alloc] initWithStackDescriptor:stackDescriptor key:stackKey];
		if (stack) {
#if defined(DEBUG)
			RXOLog(@"new stack initialized: %@", stack);
#endif			
			
			// store the new stack in the active stacks dictionary
			pthread_rwlock_wrlock(&_activeStacksLock);
			[_activeStacks setObject:stack forKey:stackKey];
			pthread_rwlock_unlock(&_activeStacksLock);
			
			// give up ownership of the new stack
			[stack release];
			
			// give up the read lock
			pthread_rwlock_unlock(&_stackCreationLock);
			[self postStackLoadedNotification_:stackKey];
		} else {
			@throw [NSException exceptionWithName:@"RXStackCreationFailureException" reason:@"Stack creation failed." userInfo:stackDescriptor];
		}
	} @catch (NSException* e) {
#if defined(DEBUG)
		RXOLog(@"stack creation failed: %@", e);
#endif
		// make sure there is no stack for the stack key
		pthread_rwlock_wrlock(&_activeStacksLock);
		[_activeStacks removeObjectForKey:stackKey];
		pthread_rwlock_unlock(&_activeStacksLock);
		
		// give up the read lock
		pthread_rwlock_unlock(&_stackCreationLock);
		
		// notify the user through the GUI
		[self performSelectorOnMainThread:@selector(notifyUserOfFatalException:) withObject:e waitUntilDone:NO];
	} @finally {
		// signal if we were asked to
		if (signal)
			semaphore_signal(_stackInitSemaphore);
	}
}

- (void)loadStackWithKey:(NSString*)stackKey waitUntilDone:(BOOL)waitFlag {
	// NOTE: this method can run on any thread
	if (_tornDown)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"loadStackWithKey: RXWorld IS TORN DOWN" userInfo:nil];
	
	// fire the stack on a new thread
	NSDictionary* initStackDict = [NSDictionary dictionaryWithObjectsAndKeys:stackKey, @"stackKey", [NSNumber numberWithBool:waitFlag], @"waitFlag", nil];
	[self performSelector:@selector(_initializeStackWithInitializationDictionary:) withObject:initStackDict inThread:_stackThread];
	
	// if the request is synchronous, wait until we get signaled
	if (waitFlag)
		semaphore_wait(_stackInitSemaphore);
}

- (RXStack*)activeStackWithKey:(NSString*)key {
	if (_tornDown)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"activeStacks: RXWorld IS TORN DOWN" userInfo:nil];
	
	pthread_rwlock_rdlock(&_activeStacksLock);
	RXStack* stack = [_activeStacks objectForKey:key];
	pthread_rwlock_unlock(&_activeStacksLock);
	
	return stack;
}

- (NSArray*)activeStacks {
	if (_tornDown)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"activeStacks: RXWorld IS TORN DOWN" userInfo:nil];
	
	pthread_rwlock_rdlock(&_activeStacksLock);
	NSArray* stacks = [_activeStacks allValues];
	pthread_rwlock_unlock(&_activeStacksLock);
	
	return stacks;
}

#pragma mark -

- (NSURL*)worldBase {
	// this method can run on any thread
	return _worldBase;
}

- (NSURL*)worldUserBase {
	return _worldUserBase;
}

- (MHKArchive*)extraBitmapsArchive {
	return _extraBitmapsArchive;
}

- (NSDictionary*)extraBitmapsDescriptor {
	return _extrasDescriptor;
}

- (NSView <RXWorldViewProtocol> *)worldView {
	return _worldView;
}

- (NSCursor*)defaultCursor {
	return [self cursorForID:3000];
}

- (NSCursor*)openHandCursor {
	return [self cursorForID:2003];
}

- (NSCursor*)invisibleCursor {
	return [self cursorForID:9000];
}

- (NSCursor*)cursorForID:(uint16_t)ID {
	uintptr_t key = ID;
	return (NSCursor*)NSMapGet(_cursors, (const void*)key);
}

#pragma mark -

- (void*)audioRenderer {
	return _audioRenderer;
}

- (RXStateCompositor*)stateCompositor {
	return _stateCompositor;
}

#pragma mark -

- (RXRenderState*)cyanMovieRenderState {
	return _cyanMovieState;
}

- (RXRenderState*)cardRenderState {
	return _cardState;
}

- (RXRenderState*)creditsRenderState {
	return _creditsState;
}

#pragma mark -

- (RXGameState*)gameState {
	return _gameState;
}

- (void)_activeCardDidChange:(NSNotification*)notification {
	// WARNING: WILL RUN ON THE MAIN THREAD
	NSError* error;
	
	// if we have a new game state to load and we just cleared the active card, do the swap
	if (![notification object] && _gameStateToLoad) {	
		// swap the game state
		[_gameState release];
		_gameState = _gameStateToLoad;
		_gameStateToLoad = nil;
		
		// make the new game's edition current
		if (![[RXEditionManager sharedEditionManager] makeEditionCurrent:[_gameState edition] rememberChoice:NO error:&error]) {
			[NSApp presentError:error];
			return;
		}
		
		// set the active card to that of the new game state
		RXSimpleCardDescriptor* scd = [_gameState currentCard];
		[(RXCardState*)_cardState setActiveCardWithStack:scd->parentName ID:scd->cardID waitUntilDone:NO];
		
		// fade the card state back in
		[_stateCompositor fadeInState:_cardState over:1.0 completionDelegate:self completionSelector:@selector(_cardStateWasFadedIn:)];
	}
}

- (void)_cardStateWasFadedIn:(RXRenderState*)state {

}

- (void)_cardStateWasFadedOut:(RXRenderState*)state {
	[(RXCardState*)_cardState clearActiveCardWaitingUntilDone:NO];
}

- (BOOL)loadGameState:(RXGameState*)gameState error:(NSError**)error {
	_gameStateToLoad = [gameState retain];
	[_stateCompositor fadeOutState:_cardState over:1.0 completionDelegate:self completionSelector:@selector(_cardStateWasFadedOut:)];
	return YES;
}

#pragma mark -

- (void)_dumpEngineVariables {
	pthread_mutex_lock(&_engineVariablesMutex);
	RXOLog(@"dumping engine variables\n%@", _engineVariables);
	pthread_mutex_unlock(&_engineVariablesMutex);
}

- (NSMutableDictionary*)rendering {
	return [_engineVariables objectForKey:@"rendering"];
}

- (id)valueForUndefinedKey:(NSString*)key {
	if (!_engineVariables)
		return nil;
	
	pthread_mutex_lock(&_engineVariablesMutex);
	id v = [_engineVariables valueForKeyPath:key];
	pthread_mutex_unlock(&_engineVariablesMutex);
	
	return v;
}

- (void)setValue:(id)value forUndefinedKey:(NSString*)key {
	if (!_engineVariables)
		return;
	
	pthread_mutex_lock(&_engineVariablesMutex);
	[_engineVariables setValue:value forKeyPath:key];
	pthread_mutex_unlock(&_engineVariablesMutex);
}

@end
