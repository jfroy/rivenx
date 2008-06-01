//
//	RXWorldRendering.mm
//	rivenx
//
//	Created by Jean-Francois Roy on 04/09/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import "RXWorldView.h"
#import "RXWorld.h"

#import "RXCardState.h"
#import "RXCreditsState.h"
#import "RXCyanMovieState.h"

#import "NSFontAdditions.h"

#import "RXAudioRenderer.h"


@implementation RXWorld (RXWorldRendering)

- (void)setInitialCard_:(NSNotification *)notification {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"RXStackDidLoadNotification" object:nil];
#if defined(DEBUG)
	RXOLog(@"responding to a RXStackDidLoadNotification notification by loading the entry card of stack aspit");
#endif
	[(RXCardState *)_cardState setActiveCardWithStack:@"aspit" ID:[[self activeStackWithKey:@"aspit"] entryCardID] waitUntilDone:NO];
	[_stateCompositor setOpacity:1.0f ofState:_cardState];
}

- (void)_initializeRendering {
	// WARNING: the world has to run on the main thread
	if (!pthread_main_np()) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_initializeRenderer: MAIN THREAD ONLY" userInfo:nil];
	
	// initialize the audio renderer
	RX::AudioRenderer* audioRenderer = new RX::AudioRenderer();
	_audioRenderer = reinterpret_cast<void *>(audioRenderer);
	audioRenderer->Initialize();
	
	// create our window on the main screen, centered
	NSScreen* mainScreen = [NSScreen mainScreen];
	NSRect screenRect = [mainScreen frame];
	NSWindow* renderWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0f, 0.0f, 640.0f, 480.0f)
														 styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSNormalWindowLevel
														   backing:NSBackingStoreBuffered
															 defer:YES
															screen:mainScreen];
	[renderWindow setTitle:@"Riven X"];
	[renderWindow setReleasedWhenClosed:YES];
	[renderWindow setAcceptsMouseMovedEvents:YES];
	[renderWindow setFrameOrigin:NSMakePoint((screenRect.size.width / 2) - 320.0f, (screenRect.size.height / 2) - 240.0f)];
	[renderWindow setDelegate:[NSApp delegate]];
	
	// allocate the world view
	NSRect contentViewRect = [renderWindow contentRectForFrameRect:[renderWindow frame]];
	contentViewRect.origin.x = 0;
	contentViewRect.origin.y = 0;
	_worldView = [[RXWorldView alloc] initWithFrame:contentViewRect];
	
	// set the world view as the content view
	[renderWindow setContentView:_worldView];
	[_worldView release];
	
	// initialize the texture broker
//	_textureBroker = [RXTextureBroker new];
	
	// initialize the state compositor
	_stateCompositor = [[RXStateCompositor alloc] init];
	
	// show the window
	[renderWindow makeKeyAndOrderFront:self];
	
	// start the audio renderer
	audioRenderer->Start();
}

- (void)_initializeRenderStates {
	// prep the cyan state
	_cyanMovieState = [[RXCyanMovieState alloc] init];
	[_cyanMovieState setDelegate:_stateCompositor];
	
	// prep the credits state
	//_creditsState = [[RXCreditsState alloc] init];
	//[_creditsState setDelegate:_stateCompositor];
	
	// prep the card state
	_cardState = [[RXCardState alloc] init];
	[_cardState setDelegate:_stateCompositor];
	
	// Add states to the state compositor
	//[_stateCompositor addState:_cyanMovieState opacity:1.0f];
	[_stateCompositor addState:_cardState opacity:1.0f];
	
	// When the aspit stack finishes loading, we'll be notified
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setInitialCard_:) name:@"RXStackDidLoadNotification" object:nil];
}

@end
