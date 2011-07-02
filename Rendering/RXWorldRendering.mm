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
    NSString* encoded_frame = [[NSUserDefaults standardUserDefaults] objectForKey:@"WindowFrame"];
    if (encoded_frame) {
        NSRect saved_frame = NSRectFromString(encoded_frame);
        [_window setFrameOrigin:saved_frame.origin];
    } else {
        NSRect screen_frame = [screen frame];
        [_window setFrameOrigin:NSMakePoint(screen_frame.origin.x + (screen_frame.size.width / 2) - ([_window frame].size.width / 2),
                                            screen_frame.origin.y + (screen_frame.size.height / 2) - ([_window frame].size.height / 2))];
    }
    [_window setCanHide:YES];
    [self _initializeRenderingWindow:_window];
}

- (NSWindow*)_renderingWindow {
    return (_fullscreen) ? _fullscreenWindow : _window;
}

- (void)_toggleFullscreen {
    // the _fullscreen attribute has been updated when this is called
    NSWindow* window = [self _renderingWindow];
    NSWindow* oldWindow = [_worldView window];
    
    [oldWindow orderOut:self];
    [_worldView removeFromSuperviewWithoutNeedingDisplay];
    
    [window setContentView:_worldView];
    [window makeKeyAndOrderFront:self];
}

- (void)windowWillClose:(NSNotification*)notification {
    [NSApp terminate:nil];
}

- (void)windowDidChangeScreen:(NSNotification*)notification {
    // if the window-mode window has been moved to a different screen, we need to move the fullscreen window along
    NSWindow* window = [notification object];
    if (window == _fullscreenWindow)
        return;
    
    [_fullscreenWindow setFrame:[[window screen] frame] display:NO];
}

- (void)windowDidMove:(NSNotification*)notification {
    // save the frame of the window-mode window so that we can place the window at the same location
    // on a subsequent launch (or put the fullscreen window on the right screen)
    NSWindow* window = [notification object];
    if (window == _fullscreenWindow)
        return;
    
    NSString* encoded_frame = NSStringFromRect([window frame]);
    [[NSUserDefaults standardUserDefaults] setObject:encoded_frame forKey:@"WindowFrame"];
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
    
    // set the initial fullscreen state
    _fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"Fullscreen"];
    
    // get the saved window frame and determine the best screen to use if we're going to start fullscreen
    NSString* encoded_frame = [[NSUserDefaults standardUserDefaults] objectForKey:@"WindowFrame"];
    NSScreen* best_screen = [NSScreen mainScreen];
    if (encoded_frame) {
        NSRect saved_frame = NSRectFromString(encoded_frame);
        CGFloat max_area = 0.0;
        
        NSEnumerator* screen_enum = [[NSScreen screens] objectEnumerator];
        NSScreen* screen;
        while ((screen = [screen_enum nextObject])) {
            NSRect intersection = NSIntersectionRect([screen frame], saved_frame);
            CGFloat area = intersection.size.width * intersection.size.height;
            if (area > max_area) {
                max_area = area;
                best_screen = screen;
            }
        }
        
        // if max_area is 0, the saved frame is not on any active screen; simpy clear out the saved frame
        if (max_area == 0.0)
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"WindowFrame"];
    }
    
    // create our windows
    [self _initializeWindow:best_screen];
    [self _initializeFullscreenWindow:best_screen];
    
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
#if !__LP64__
    EnterMovies();
#endif
}

@end
