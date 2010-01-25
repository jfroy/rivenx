//
//  RXWorldRendering.mm
//  rivenx
//
//  Created by Jean-Francois Roy on 04/09/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import "Engine/RXWorld.h"
#import "Engine/RXEditionManager.h"

#import "Rendering/Audio/RXAudioRenderer.h"
#import "Rendering/Graphics/RXDynamicPicture.h"
#import "Rendering/Graphics/RXWorldView.h"
#import "Rendering/Graphics/GL/GLShaderProgramManager.h"

#import "States/RXCardState.h"


@implementation RXWorld (RXWorldRendering)

- (void)_initializeRendering {
    // WARNING: the world has to run on the main thread
    if (!pthread_main_np())
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_initializeRenderer: MAIN THREAD ONLY" userInfo:nil];
    
    // initialize the audio renderer
    RX::AudioRenderer* audioRenderer = new RX::AudioRenderer();
    _audioRenderer = reinterpret_cast<void *>(audioRenderer);
    audioRenderer->Initialize();
    
    // we can now observe the volume key path rendering setting
    [[_engineVariables objectForKey:@"rendering"] addObserver:self
                                                   forKeyPath:@"volume"
                                                      options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                                                      context:[_engineVariables objectForKey:@"rendering"]];
    
    // FIXME: we should store the last screen ID (index? some other?) used and keep using that
    // create our window on the main screen
    NSScreen* mainScreen = [NSScreen mainScreen];
    NSRect screenRect = [mainScreen frame];
    NSWindow* renderWindow;
//    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"FullScreenMode"]) {
//        // create fullscreen, borderless window
//        renderWindow = [[NSWindow alloc] initWithContentRect:screenRect
//                                                   styleMask:NSBorderlessWindowMask
//                                                     backing:NSBackingStoreBuffered
//                                                       defer:NO
//                                                      screen:mainScreen];
//        [renderWindow setLevel:NSTornOffMenuWindowLevel];
//        if ([renderWindow respondsToSelector:@selector(setCollectionBehavior:)])
//            [renderWindow setCollectionBehavior:NSWindowCollectionBehaviorDefault];
//    } else {
        // regular window
    renderWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0f, 0.0f, kRXRendererViewportSize.width, kRXRendererViewportSize.height)
                                               styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
                                                 backing:NSBackingStoreBuffered
                                                   defer:YES
                                                  screen:mainScreen];
    
    [renderWindow setLevel:NSNormalWindowLevel];
    [renderWindow setFrameOrigin:NSMakePoint((screenRect.size.width / 2) - ([renderWindow frame].size.width / 2),
                                             (screenRect.size.height / 2) - ([renderWindow frame].size.height / 2))];
    
    [renderWindow setAcceptsMouseMovedEvents:YES];
    [renderWindow setCanHide:YES];
    [renderWindow setDelegate:[NSApp delegate]];
    [renderWindow setDisplaysWhenScreenProfileChanges:YES];
    [renderWindow setReleasedWhenClosed:YES];
    [renderWindow setTitle:@"Riven X"];
    
    // allocate the world view (which will create the GL contexts)
    NSRect contentViewRect = [renderWindow contentRectForFrameRect:[renderWindow frame]];
    contentViewRect.origin.x = 0;
    contentViewRect.origin.y = 0;
    _worldView = [[RXWorldView alloc] initWithFrame:contentViewRect];
        
    // initialize the shader manager
    [GLShaderProgramManager sharedManager];
    
    // initialize the dynamic picture unpack buffer
    [RXDynamicPicture sharedDynamicPictureUnpackBuffer];
    
    // initialize the card renderer
    _cardRenderer = [[RXCardState alloc] init];
    [_worldView setCardRenderer:_cardRenderer];
    
    // set the world view as the content view
    [renderWindow setContentView:_worldView];
    [_worldView release];
    
    // if we're in fullscreen mode, hide the menu bar now
//    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"FullScreenMode"])
//        [NSMenu setMenuBarVisible:NO];
    
    // show the window
    [renderWindow makeKeyAndOrderFront:self];
    
    // start the audio renderer
    audioRenderer->Start();
    
    // initialize QuickTime
    EnterMovies();
}

@end
