//
//  RXWorldRendering.mm
//  rivenx
//
//  Created by Jean-Francois Roy on 04/09/2005.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "Engine/RXWorld.h"

#import "Rendering/Audio/RXAudioRenderer.h"
#import "Rendering/Graphics/RXDynamicPicture.h"
#import "Rendering/Graphics/RXWorldView.h"
#import "Rendering/Graphics/RXWindow.h"
#import "Rendering/Graphics/GL/GLShaderProgramManager.h"

#import "States/RXCardState.h"

#import "Utilities/GTMSystemVersion.h"


@implementation RXWorld (RXWorldRendering)

- (void)_initializeRenderingWindow:(NSWindow*)window {
    [window setTitle:@"Riven X"];
    [window setAcceptsMouseMovedEvents:YES];
    [window setDelegate:(id <NSWindowDelegate>)self];
    [window setDisplaysWhenScreenProfileChanges:YES];
    [window setReleasedWhenClosed:YES];
    [window setShowsResizeIndicator:NO];
    
    [window orderOut:self];
}

- (void)_initializeFullscreenWindow:(NSScreen*)screen {
    // create a fullscreen, borderless window
    _fullscreenWindow = [[RXWindow alloc] initWithContentRect:[screen frame]
                                                    styleMask:NSBorderlessWindowMask
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO
                                                       screen:screen];
    
    [_fullscreenWindow setLevel:NSStatusWindowLevel + 1];
    [_fullscreenWindow setFrameOrigin:NSZeroPoint];
    [_fullscreenWindow setCanHide:NO];
    [self _initializeRenderingWindow:_fullscreenWindow];
    
    // we need to manually enable cursor rects and set the collection behavior back to managed because the window is borderless
    [_fullscreenWindow enableCursorRects];
    if ([_fullscreenWindow respondsToSelector:@selector(setCollectionBehavior:)])
        [_fullscreenWindow setCollectionBehavior:NSWindowCollectionBehaviorManaged];
}

- (void)_initializeWindow:(NSScreen*)screen {
    // create a regular window
    _window = [[RXWindow alloc] initWithContentRect:NSMakeRect(0.0f, 0.0f, kRXRendererViewportSize.width, kRXRendererViewportSize.height)
                                          styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
                                            backing:NSBackingStoreBuffered
                                              defer:YES
                                             screen:screen];
    
    [_window setLevel:NSNormalWindowLevel];
    NSRect screenRect = [screen frame];
    [_window setFrameOrigin:NSMakePoint((screenRect.size.width / 2) - ([_window frame].size.width / 2),
                                        (screenRect.size.height / 2) - ([_window frame].size.height / 2))];
    [_window setCanHide:YES];
    [self _initializeRenderingWindow:_window];
}

- (NSWindow*)_renderingWindow {
    return (_fullscreen) ? _fullscreenWindow : _window;
}

- (void)_toggleFullscreenSnow {
    if (_fullscreen) {
        _defaultPresentationOptions = [NSApp presentationOptions];
        [NSApp setPresentationOptions:(NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar)];
        
        [_window setLevel:NSStatusWindowLevel + 1];
        [_window setStyleMask:NSBorderlessWindowMask];
        [_window setFrame:[[_window screen] frame] display:YES animate:YES];
        [_window setCanHide:NO];
        [_window enableCursorRects];
        [_window setCollectionBehavior:NSWindowCollectionBehaviorManaged];
    } else {
        [NSApp setPresentationOptions:_defaultPresentationOptions];
        
        [_window setLevel:NSNormalWindowLevel];
        [_window setStyleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask];
        
        NSRect screenRect = [[_window screen] frame];
        NSRect contentViewRect = NSMakeRect(0, 0, kRXRendererViewportSize.width, kRXRendererViewportSize.height);
        NSRect windowRect = [_window frameRectForContentRect:contentViewRect];
        windowRect.origin = NSMakePoint((screenRect.size.width / 2) - (windowRect.size.width / 2),
                                        (screenRect.size.height / 2) - (windowRect.size.height / 2));
        [_window setFrame:windowRect display:YES animate:YES];
        
        [_window setCanHide:YES];
        [_window enableCursorRects];
        [_window setCollectionBehavior:NSWindowCollectionBehaviorManaged];
    }
}

- (void)_toggleFullscreen {
    // the _fullscreen attribute has been updated when this is called
    NSWindow* window = [self _renderingWindow];
    NSWindow* oldWindow = [_worldView window];
    
    [oldWindow orderOut:self];
    [_worldView removeFromSuperviewWithoutNeedingDisplay];
    
    [window setContentView:_worldView];
    [window makeKeyAndOrderFront:self];
    
    [_worldView setUseCoreImage:_fullscreen];
}

- (void)windowWillClose:(NSNotification*)notification {
    [NSApp terminate:nil];
}

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
    
    // create our windows on the main screen; on Snow Leopard and later, we only need one window
    NSScreen* mainScreen = [NSScreen mainScreen];
    [self _initializeWindow:mainScreen];
    [self _initializeFullscreenWindow:mainScreen];
    
    // set the initial fullscreen state
    _fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"Fullscreen"];
    
    NSWindow* window = [self _renderingWindow];
    
    // allocate the world view (which will create the GL contexts)
    NSRect contentViewRect = [window contentRectForFrameRect:[window frame]];
    _worldView = [[RXWorldView alloc] initWithFrame:contentViewRect];
    
    // initialize the shader manager
    [GLShaderProgramManager sharedManager];
    
    // initialize the dynamic picture unpack buffer
    [RXDynamicPicture sharedDynamicPictureUnpackBuffer];
    
    // initialize the card renderer
    _cardRenderer = [[RXCardState alloc] init];
    [_worldView setCardRenderer:_cardRenderer];
    
    // set the world view as the content view
    [window setContentView:_worldView];
    
    // show the window
    [window makeKeyAndOrderFront:self];
    
    // start the audio renderer
    audioRenderer->Start();
    
    // initialize QuickTime
    EnterMovies();
}

@end
