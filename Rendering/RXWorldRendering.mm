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

#import "Utilities/platform_info.h"
#import "Utilities/NSString+RXStringAdditions.h"


@implementation RXWorld (RXWorldRendering)

- (void)_initializeRenderingWindow:(NSWindow*)window
{
    [window setTitle:@"Riven X"];
    [window setAcceptsMouseMovedEvents:YES];
    [window setDelegate:(id <NSWindowDelegate>)self];
    [window setDisplaysWhenScreenProfileChanges:YES];
    [window setReleasedWhenClosed:YES];
    [window setShowsResizeIndicator:NO];
    
    [window orderOut:self];
}

- (void)_initializeFullscreenWindow:(NSScreen*)screen
{
    // create a fullscreen, borderless window
    _fullscreenWindow = [[RXWindow alloc] initWithContentRect:[screen frame] styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO
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

- (void)_initializeWindow:(NSScreen*)screen
{
    // create a regular window
    _window = [[RXWindow alloc] initWithContentRect:NSMakeRect(0.0f, 0.0f, kRXRendererViewportSize.width, kRXRendererViewportSize.height)
        styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask backing:NSBackingStoreBuffered defer:YES screen:screen];
    
    [_window setLevel:NSNormalWindowLevel];
    [_window setCanHide:YES];

    bool preLion = [[copy_system_version() autorelease] rx_versionIsOlderThan:@"10.7"];
    NSWindowCollectionBehavior behavior = NSWindowCollectionBehaviorManaged | NSWindowCollectionBehaviorParticipatesInCycle;
    if (!preLion)
        behavior |= NSWindowCollectionBehaviorFullScreenPrimary;
    [_window setCollectionBehavior:behavior];
    
    NSString* encoded_frame = [[NSUserDefaults standardUserDefaults] objectForKey:@"WindowFrame"];
    if (encoded_frame)
    {
        NSRect saved_frame = NSRectFromString(encoded_frame);
        [_window setFrameOrigin:saved_frame.origin];
    }
    else
    {
        NSRect screen_frame = [screen frame];
        [_window setFrameOrigin:NSMakePoint(screen_frame.origin.x + (screen_frame.size.width / 2) - ([_window frame].size.width / 2),
                                            screen_frame.origin.y + (screen_frame.size.height / 2) - ([_window frame].size.height / 2))];
    }
    
    [self _initializeRenderingWindow:_window];
}

- (NSWindow*)_renderingWindow
{
    return (_fullscreen) ? _fullscreenWindow : _window;
}

- (void)_handleFullscreeenModeChange
{
    [[NSUserDefaults standardUserDefaults] setBool:_fullscreen forKey:@"Fullscreen"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RXFullscreenModeChangeNotification" object:nil userInfo:nil];
}

- (void)_toggleFullscreenLegacyPath
{
    bool fullscreen = _fullscreen;

    if (!fullscreen)
        [self windowWillEnterFullScreen:nil];

    // the _fullscreen attribute has been updated when this is called
    NSWindow* window = [self _renderingWindow];
    NSWindow* oldWindow = [_worldView window];

    [oldWindow orderOut:self];

    CGLContextObj renderContext = [_worldView renderContext];
    CGLContextObj loadContext = [_worldView loadContext];
    CGLLockContext(renderContext);
    CGLLockContext(loadContext);

    CVDisplayLinkStop([_worldView displayLink]);

    [_worldView removeFromSuperviewWithoutNeedingDisplay];
    [window setContentView:_worldView];

    CGLUnlockContext(renderContext);
    CGLUnlockContext(loadContext);

    [window makeKeyAndOrderFront:self];

    CVDisplayLinkStart([_worldView displayLink]);

    if (fullscreen)
        [self windowDidExitFullScreen:nil];
}

- (NSSize)window:(NSWindow*)window willUseFullScreenContentSize:(NSSize)proposedSize
{
    return proposedSize;
}

- (NSApplicationPresentationOptions)window:(NSWindow*)window willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposedOptions
{
    return NSApplicationPresentationFullScreen | NSApplicationPresentationHideDock | NSApplicationPresentationAutoHideMenuBar |
        NSApplicationPresentationDisableAppleMenu | NSApplicationPresentationDisableSessionTermination | NSApplicationPresentationDisableHideApplication;
}

- (NSArray*)customWindowsToEnterFullScreenForWindow:(NSWindow*)window
{
    return [NSArray arrayWithObject:window];
}

- (void)window:(NSWindow*)window startCustomAnimationToEnterFullScreenWithDuration:(NSTimeInterval)duration
{
    CVDisplayLinkStop([_worldView displayLink]);

    NSInteger previousWindowLevel = [window level];
    [window setLevel:(NSMainMenuWindowLevel + 1)];

    NSString* encoded_frame = NSStringFromRect([window frame]);
    [[NSUserDefaults standardUserDefaults] setObject:encoded_frame forKey:@"WindowFrame"];

    [window setStyleMask:([window styleMask] | NSFullScreenWindowMask)];

    NSScreen* screen = [window screen];
    NSRect screenFrame = [screen frame];
    
    NSRect fullscreenFrame;
    fullscreenFrame.size = [self window:window willUseFullScreenContentSize:screenFrame.size];
    fullscreenFrame.origin.x = (screenFrame.size.width - fullscreenFrame.size.width) * 0.5;
    fullscreenFrame.origin.y = (screenFrame.size.height - fullscreenFrame.size.height) * 0.5;
    
    NSRect centerScreenWindowFrame;
    centerScreenWindowFrame.origin.x = (screenFrame.size.width - window.frame.size.width) * 0.5;
    centerScreenWindowFrame.origin.y = (screenFrame.size.height - window.frame.size.height) * 0.5;
    centerScreenWindowFrame.size = window.frame.size;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context)
    {
        [context setDuration:duration/2];
        [[window animator] setFrame:centerScreenWindowFrame display:YES];
    }
    completionHandler:^(void)
    {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context)
        {
            [context setDuration:duration/2];
            [[window animator] setFrame:fullscreenFrame display:YES];
            
        }
        completionHandler:^(void)
        {
            [window setLevel:previousWindowLevel];

            CVDisplayLinkStart([_worldView displayLink]);
        }];
    }];
}

- (NSArray*)customWindowsToExitFullScreenForWindow:(NSWindow*)window
{
    return [NSArray arrayWithObject:window];
}

- (void)window:(NSWindow*)window startCustomAnimationToExitFullScreenWithDuration:(NSTimeInterval)duration
{
    CVDisplayLinkStop([_worldView displayLink]);

    reinterpret_cast<RXWindow*>(window).constrainingToScreenSuspended = YES;

    NSString* encoded_frame = [[NSUserDefaults standardUserDefaults] objectForKey:@"WindowFrame"];
    NSRect frame = NSRectFromString(encoded_frame);
    
    NSRect centerScreenWindowFrame;
    centerScreenWindowFrame.origin.x = (window.frame.size.width - frame.size.width) * 0.5;
    centerScreenWindowFrame.origin.y = (window.frame.size.height - frame.size.height) * 0.5;
    centerScreenWindowFrame.size = frame.size;

    NSInteger previousWindowLevel = [window level];
    [window setLevel:(NSMainMenuWindowLevel + 1)];

    [window setStyleMask:([window styleMask] & ~NSFullScreenWindowMask)];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context)
    {
        [context setDuration:duration/2];
        [[window animator] setFrame:centerScreenWindowFrame display:YES];
    }
    completionHandler:^(void)
    {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context)
        {
            [context setDuration:duration/2];
            [[window animator] setFrame:frame display:YES];
        }
        completionHandler:^(void)
        {
            reinterpret_cast<RXWindow*>(window).constrainingToScreenSuspended = NO;
            [window setLevel:previousWindowLevel];

            CVDisplayLinkStart([_worldView displayLink]);
        }];

    }];
}

- (void)windowWillEnterFullScreen:(NSNotification*)notification
{
    _fullscreen = YES;
    [self _handleFullscreeenModeChange];
}

- (void)windowDidExitFullScreen:(NSNotification*)notification
{
    _fullscreen = NO;
    [self _handleFullscreeenModeChange];
}

- (void)windowWillClose:(NSNotification*)notification
{
    [_worldView tearDown];
    [NSApp terminate:nil];
}

- (void)windowDidChangeScreen:(NSNotification*)notification
{
    // if the window-mode window has been moved to a different screen, we need to move the fullscreen window along
    NSWindow* window = [notification object];
    if (window == _fullscreenWindow)
        return;
    
    [_fullscreenWindow setFrame:[[window screen] frame] display:NO];
}

- (void)windowDidMove:(NSNotification*)notification
{
    // save the frame of the window-mode window so that we can place the window at the same location
    // on a subsequent launch (or put the fullscreen window on the right screen)
    NSWindow* window = [notification object];
    if (window == _fullscreenWindow || _fullscreen)
        return;
    
    NSString* encoded_frame = NSStringFromRect([window frame]);
    [[NSUserDefaults standardUserDefaults] setObject:encoded_frame forKey:@"WindowFrame"];
}

#pragma mark -

- (void)_initializeRendering
{
    // WARNING: the world has to run on the main thread
    if (!pthread_main_np())
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_initializeRenderer: MAIN THREAD ONLY" userInfo:nil];

    bool preLion = [[copy_system_version() autorelease] rx_versionIsOlderThan:@"10.7"];

    // initialize the audio renderer
    RX::AudioRenderer* audioRenderer = new RX::AudioRenderer();
    _audioRenderer = reinterpret_cast<void *>(audioRenderer);
    audioRenderer->Initialize();

    // initialize QuickTime
#if !__LP64__
    EnterMovies();
#endif
    
    // we can now observe the volume key path rendering setting
    [[_engineVariables objectForKey:@"rendering"] addObserver:self forKeyPath:@"volume" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
        context:[_engineVariables objectForKey:@"rendering"]];
    
    // set the initial fullscreen state
    _fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"Fullscreen"];

    // get the saved window frame and determine the best screen to use if we're going to start fullscreen
    NSString* encoded_frame = [[NSUserDefaults standardUserDefaults] objectForKey:@"WindowFrame"];
    NSScreen* best_screen = [NSScreen mainScreen];
    if (encoded_frame)
    {
        NSRect saved_frame = NSRectFromString(encoded_frame);
        CGFloat max_area = 0.0;
        
        NSEnumerator* screen_enum = [[NSScreen screens] objectEnumerator];
        NSScreen* screen;
        while ((screen = [screen_enum nextObject]))
        {
            NSRect intersection = NSIntersectionRect([screen frame], saved_frame);
            CGFloat area = intersection.size.width * intersection.size.height;
            if (area > max_area)
            {
                max_area = area;
                best_screen = screen;
            }
        }

        // if max_area is 0, the saved frame is not on any active screen; simpy clear out the saved frame
        if (max_area == 0.0)
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"WindowFrame"];
    }
    
    // create our windows
    NSWindow* window;

    [self _initializeWindow:best_screen];
    if (preLion)
    {
        [self _initializeFullscreenWindow:best_screen];
        window = [self _renderingWindow];
    }
    else
    {
        window = _window;
    }
    
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

    if (!preLion && _fullscreen)
    {
        [window toggleFullScreen:self];
    }

    // start the audio renderer
    audioRenderer->Start();
}

@end
