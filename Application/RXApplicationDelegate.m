//
//  RXApplicationDelegate.m
//  rivenx
//
//  Created by Jean-Francois Roy on 30/08/2005.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import <ExceptionHandling/NSExceptionHandler.h>

#import <Foundation/NSBundle.h>
#import <Foundation/NSTimer.h>

#import <AppKit/NSAlert.h>
#import <AppKit/NSDocumentController.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSOpenPanel.h>
#import <AppKit/NSWindow.h>

#import <Sparkle/SUUpdater.h>

#import "Application/RXVersionComparator.h"
#import "Application/RXWelcomeWindowController.h"

#import "Application/RXApplicationDelegate.h"

#import "Engine/RXWorld.h"

#import "Rendering/Graphics/RXWorldView.h"

#import "Debug/RXDebug.h"
#import "Debug/RXDebugWindowController.h"

#import "Utilities/BZFSUtilities.h"


@interface RXApplicationDelegate (RXApplicationDelegate_Private)
- (BOOL)_openGameWithURL:(NSURL*)url addToRecents:(BOOL)addToRecents;
- (void)_autosave:(NSTimer*)timer;
@end

@implementation RXApplicationDelegate

+ (void)initialize
{
    [super initialize];
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:NO], @"Fullscreen",
        [NSDictionary dictionary], @"EngineVariables",
        nil
    ]];
}

#pragma mark -
#pragma mark debug UI

#if defined(DEBUG)
- (void)_showDebugConsole:(id)sender
{
    [debugConsoleWC showWindow:sender];
}

- (void)_initDebugUI
{
    debugConsoleWC = [[RXDebugWindowController alloc] initWithWindowNibName:@"DebugConsole"];
    
    NSMenu* debugMenu = [[NSMenu alloc] initWithTitle:@"Debug"];
    [debugMenu addItemWithTitle:@"Console" action:@selector(_showDebugConsole:) keyEquivalent:@""];
    
    NSMenuItem* debugMenuItem = [[NSMenuItem alloc] initWithTitle:@"Debug" action:NULL keyEquivalent:@""];
    [debugMenuItem setSubmenu:debugMenu];
    [[NSApp mainMenu] addItem:debugMenuItem];
    
    [debugMenu release];
    [debugMenuItem release];
}
#endif

#pragma mark -
#pragma mark error handling

- (BOOL)attemptRecoveryFromError:(NSError*)error optionIndex:(NSUInteger)recoveryOptionIndex
{
    if ([error domain] == RXErrorDomain)
    {
        switch ([error code])
        {
            case kRXErrQuickTimeTooOld:
                if (recoveryOptionIndex == 0)
                {
                    // once to launch SU, and another time to make sure it becomes the active application
                    [[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:@"com.apple.SoftwareUpdate" options:0 additionalEventParamDescriptor:nil
                        launchIdentifier:NULL];
                    [[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:@"com.apple.SoftwareUpdate" options:0 additionalEventParamDescriptor:nil
                        launchIdentifier:NULL];
                }
                
                // check for an app update before quitting
                [[SUUpdater sharedUpdater] checkForUpdatesInBackground];
                break;
            
            case kRXErrFailedToInitializeStack:
                if (recoveryOptionIndex == 1)
                {
                    [[RXWorld sharedWorld] setIsInstalled:NO];
                    
                    // delete the cache base directory's content
                    NSString* cache_base = [[(RXWorld*)g_world worldCacheBase] path];
                    NSArray* content = BZFSContentsOfDirectory(cache_base, NULL);
                    for (NSString* dir in content)
                        BZFSRemoveItemAtURL([NSURL fileURLWithPath:[cache_base stringByAppendingPathComponent:dir]], NULL);
                }
                [NSApp terminate:self];
                break;
            
            // installer errors are not fatal, we just want to display them
            case kRXErrInstallerMissingArchivesAfterInstall:
            case kRXErrInstallerMissingArchivesOnMedia:
                break;
            
            // fatal errors
            case kRXErrArchivesNotFound:
            case kRXErrFailedToCreatePixelFormat:
                [NSApp terminate:self];
                break;
        }
        return YES;
    }
    
    return NO;
}

- (void)notifyUserOfFatalException:(NSException*)e
{
    NSError* error = [[e userInfo] objectForKey:NSUnderlyingErrorKey];
    
    [[NSExceptionHandler defaultExceptionHandler] setExceptionHandlingMask:0];
    
    rx_print_exception_backtrace(e);
    
    [[NSExceptionHandler defaultExceptionHandler] setExceptionHandlingMask:
        NSLogUncaughtExceptionMask | NSHandleUncaughtExceptionMask |
        NSLogUncaughtRuntimeErrorMask | NSHandleUncaughtRuntimeErrorMask];

    NSAlert* failureAlert = [NSAlert new];
    [failureAlert setMessageText:[e reason]];
    [failureAlert setAlertStyle:NSWarningAlertStyle];
    [failureAlert addButtonWithTitle:NSLocalizedString(@"Quit", @"quit button")];
    
    NSDictionary* userInfo = [e userInfo];
    if (userInfo)
    {
        if (error)
            [failureAlert setInformativeText:[error localizedDescription]];
        else
            [failureAlert setInformativeText:[e name]];
    }
    else
        [failureAlert setInformativeText:[e name]];
    
    [failureAlert runModal];
    [failureAlert release];
    
    [NSApp terminate:nil];
}

- (BOOL)exceptionHandler:(NSExceptionHandler*)sender shouldLogException:(NSException*)e mask:(NSUInteger)aMask
{
    if ([[e name] isEqualToString:@"RXCommandArgumentsException"] || [[e name] isEqualToString:@"RXUnknownCommandException"] ||
        [[e name] isEqualToString:@"RXCommandError"])
    {
        return NO;
    }
    
    [self notifyUserOfFatalException:e];
    return NO;
}

- (BOOL)_checkQuickTime
{
    // check that the user has QuickTime 7.6.2 or later
    NSBundle* qtkit = [NSBundle bundleWithIdentifier:@"com.apple.QTKit"];
    release_assert(qtkit);

    NSArray* qtkit_vers = [[qtkit objectForInfoDictionaryKey:@"CFBundleShortVersionString"] componentsSeparatedByString:@"."];
    if (!qtkit_vers || [qtkit_vers count] == 0)
        qtkit_vers = [NSArray arrayWithObjects:@"0", nil];
    
    int major = ([qtkit_vers count] > 0) ? [[qtkit_vers objectAtIndex:0] intValue] : 0;
    int minor = ([qtkit_vers count] > 1) ? [[qtkit_vers objectAtIndex:1] intValue] : 0;
    int bugfix = ([qtkit_vers count] > 2) ? [[qtkit_vers objectAtIndex:2] intValue] : 0;
    
    if (major > 7 || (major == 7 && minor > 6) || (major == 7 && minor == 6 && bugfix >= 2))
        return YES;
    
    // if QuickTime is too old, tell the user about the Cinepak problem and offer them to launch SU
    NSError* error = [RXError errorWithDomain:RXErrorDomain code:kRXErrQuickTimeTooOld userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
        NSLocalizedString(@"QUICKTIME_REQUIRE_762", "require QuickTime 7.6.2"), NSLocalizedDescriptionKey,
        NSLocalizedString(@"QUICKTIME_SHOULD_UPGRADE", "should upgrade QuickTime"), NSLocalizedRecoverySuggestionErrorKey,
        [NSArray arrayWithObjects:NSLocalizedString(@"UPDATE_QUICKTIME", "update QuickTime"),
                                  NSLocalizedString(@"QUIT", "quit"), nil], NSLocalizedRecoveryOptionsErrorKey,
        self, NSRecoveryAttempterErrorKey,
        nil]];
    [NSApp presentError:error];
    return NO;
}

#pragma mark -
#pragma mark delegation and UI

- (void)applicationWillFinishLaunching:(NSNotification*)notification
{
    [[NSExceptionHandler defaultExceptionHandler] setDelegate:self];
    [[NSExceptionHandler defaultExceptionHandler] setExceptionHandlingMask:
        NSLogUncaughtExceptionMask | NSHandleUncaughtExceptionMask |
        NSLogUncaughtRuntimeErrorMask | NSHandleUncaughtRuntimeErrorMask];
    
    // check if the system's QuickTime version is compatible and return if it is not
    quicktimeGood = [self _checkQuickTime];
    
    // initialize the world
    if (quicktimeGood)
        [RXWorld sharedWorld];
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification
{
    // derive the autosave URL
    NSString* extension = [(NSString*)UTTypeCopyPreferredTagWithClass(CFSTR("org.macstorm.rivenx.game"), kUTTagClassFilenameExtension) autorelease];
    NSString* filename = [@"Autosave" stringByAppendingPathExtension:extension];
    autosaveURL = [[[[RXWorld sharedWorld] worldSupportBase] URLByAppendingPathComponent:filename isDirectory:NO] retain];
    
    // proceed no further if the QuickTime version was not suitable
    if (!quicktimeGood)
        return;
    
    // if we're not installed, start the welcome controller; otherwise, if not
    // game has been loaded, load the last save game, or a new game if no such
    // save can be found
    if (![[RXWorld sharedWorld] isInstalled])
    {
        welcomeController = [[RXWelcomeWindowController alloc] initWithWindowNibName:@"Welcome"];
        [welcomeController showWindow:nil];
    }
    else if ([[RXWorld sharedWorld] gameState] == nil)
    {
        NSArray* recentGames = [[NSDocumentController sharedDocumentController] recentDocumentURLs];
        BOOL didLoadRecent = NO;
        if ([recentGames count] > 0)
            didLoadRecent = [self _openGameWithURL:[recentGames objectAtIndex:0] addToRecents:NO];

        if (!didLoadRecent && BZFSFileURLExists(autosaveURL))
            didLoadRecent = [self _openGameWithURL:autosaveURL addToRecents:NO];

        if (!didLoadRecent)
        {
            RXGameState* gs = [[RXGameState alloc] init];
            [[RXWorld sharedWorld] loadGameState:gs];
            [gs release];
        }
        
#if defined(DEBUG)
        [self _initDebugUI];
#endif
    }
    
    // start the autosave timer
    [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(_autosave:) userInfo:nil repeats:YES];
}

- (void)applicationWillTerminate:(NSNotification*)notification
{
    // autosave and save (if the game has been saved once) before quitting
    RXGameState* gameState = [g_world gameState];
    if (gameState)
    {
        NSURL* url = [gameState URL];
        if (url && ![url isEqual:autosaveURL])
            [self saveGame:nil];
        else
            [self _autosave:nil];
    }
}

- (void)applicationWillResignActive:(NSNotification*)notification
{
    if (!g_world)
        return;
    
    wasFullscreen = [g_world fullscreen];
    if (wasFullscreen)
        [g_world toggleFullscreenLegacyPath];
}

- (void)applicationWillBecomeActive:(NSNotification*)notification
{
    if (!g_world)
        return;
    
    if (wasFullscreen)
        [g_world toggleFullscreenLegacyPath];
}

- (BOOL)application:(NSApplication*)application openFile:(NSString*)filename
{
    return [self _openGameWithURL:[NSURL fileURLWithPath:filename] addToRecents:YES];
}

- (IBAction)orderFrontAboutWindow:(id)sender
{
    static bool setup = false;
    if (!setup)
    {
        // setup the about box
        NSBundle* bundle = [NSBundle mainBundle];
        NSString* version_format = NSLocalizedStringFromTable(@"VERSION_FORMAT", @"About", nil);
        NSString* version = [NSString stringWithFormat:@"branch '%@' %@",
            NSLocalizedStringFromTable(@"BUILD_BRANCH", @"build", nil),
            NSLocalizedStringFromTable(@"BUILD_VERSION", @"build", nil)];
        
        [aboutBox center];
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wformat-nonliteral"
        [versionField setStringValue:[NSString stringWithFormat:version_format, [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"], version]];
        #pragma clang diagnostic pop
        [copyrightField setStringValue:NSLocalizedStringFromTable(@"LONG_COPYRIGHT", @"About", nil)];

        setup = true;
    }

    [aboutBox makeKeyAndOrderFront:sender];
}

- (IBAction)showAcknowledgments:(id)sender
{
    NSString* ackPath = [[NSBundle mainBundle] pathForResource:@"Riven X Acknowledgments" ofType:@"pdf"];
    [[NSWorkspace sharedWorkspace] openFile:ackPath];
}

- (IBAction)toggleFullscreen:(id)sender
{
    // legacy fullscreen path
    [g_world toggleFullscreenLegacyPath];
}

#pragma mark -
#pragma mark SUUpdater delegate

- (id <SUVersionComparison>)versionComparatorForUpdater:(SUUpdater*)updater
{
    return versionComparator;
}

- (void)quitIfNoVisibleWindows:(NSTimer*)timer
{
    NSArray* windows = [NSWindow windowNumbersWithOptions:NSWindowNumberListAllSpaces];
    if ([windows count] == 0)
        [NSApp terminate:self];
}

- (void)updater:(SUUpdater*)updater didFindValidUpdate:(SUAppcastItem*)update
{
    if (!quicktimeGood)
        [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(quitIfNoVisibleWindows:) userInfo:nil repeats:YES];
}

- (void)updaterDidNotFindUpdate:(SUUpdater*)update
{
    if (!quicktimeGood)
        [NSApp terminate:self];
}

#pragma mark -
#pragma mark game opening and saving

- (IBAction)newDocument:(id)sender
{
    if ([self isGameLoadingAndSavingDisabled])
        return;
    
    // FIXME: we need to clear the autosave somehow such that Riven X doesn't load back the card just before the end credits on the next launch
    RXGameState* gs = [[RXGameState alloc] init];
    [[RXWorld sharedWorld] loadGameState:gs];
    [gs release];
}

- (IBAction)openDocument:(id)sender
{
    if ([self isGameLoadingAndSavingDisabled])
        return;

    NSArray* dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);

    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = YES;
    panel.allowsOtherFileTypes = NO;
    panel.canSelectHiddenExtension = YES;
    panel.treatsFilePackagesAsDirectories = NO;
    panel.directoryURL = [NSURL fileURLWithPath:[dirs objectAtIndex:0] isDirectory:YES];
    panel.allowedFileTypes = [NSArray arrayWithObject:@"org.macstorm.rivenx.game"];
    
    wasFullscreen = [g_world fullscreen];
    if (wasFullscreen)
        [g_world toggleFullscreenLegacyPath];

    NSInteger result = [panel runModal];
    
    if (wasFullscreen)
        [g_world toggleFullscreenLegacyPath];

    if (result == NSOKButton)
        [self _openGameWithURL:[panel URL] addToRecents:YES];
}

- (IBAction)saveGame:(id)sender
{
    if ([self isGameLoadingAndSavingDisabled])
        return;
    
    RXGameState* gameState = [g_world gameState];
    if (!gameState)
        return;
    
    if (![gameState URL])
        [self saveGameAs:sender];
    else
    {
        NSError* error;
        if (![gameState writeToURL:[gameState URL] error:&error])
            [NSApp presentError:error];
        else
            [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[gameState URL]];
    }
}

- (IBAction)saveGameAs:(id)sender
{
    if ([self isGameLoadingAndSavingDisabled])
        return;
    
    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;
    panel.allowsOtherFileTypes = NO;
    panel.canSelectHiddenExtension = YES;
    panel.treatsFilePackagesAsDirectories = NO;
    panel.allowedFileTypes = [NSArray arrayWithObject:@"org.macstorm.rivenx.game"];
    
    [panel beginSheetModalForWindow:[g_worldView window] completionHandler:^(NSInteger result)
    {
        if (result == NSCancelButton || [self isGameLoadingAndSavingDisabled])
            return;
        
        // dismiss the panel now
        [panel orderOut:self];
        
        NSError* error = nil;
        RXGameState* gameState = [g_world gameState];
        if (![gameState writeToURL:[panel URL] error:&error])
        {
            [NSApp presentError:error];
            return;
        }
        
        // add the new save file to the recents
        [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[gameState URL]]; 
    }];
}

- (BOOL)_openGameWithURL:(NSURL*)url addToRecents:(BOOL)addToRecents
{
    NSError* error;
    
    // lie if loading and saving is disabled by returning YES to avoid the error dialog
    if ([self isGameLoadingAndSavingDisabled])
        return YES;
    
    // load the save file, and present any error to the user if one occurs
    RXGameState* gameState = [RXGameState gameStateWithURL:url error:&error];
    if (!gameState)
    {
        [NSApp presentError:error];
        return NO;
    }
    
    // load the game
    [[RXWorld sharedWorld] loadGameState:gameState];
    
    // add the save file to the recents (if requested)
    if (addToRecents)
        [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[gameState URL]];
    
    return YES;
}

- (void)_autosave:(NSTimer*)timer
{
    if ([self isGameLoadingAndSavingDisabled])
    {
        missedAutosave = YES;
        return;
    }
    missedAutosave = NO;
    
    RXGameState* gameState = [g_world gameState];
    if (!gameState)
        return;
    
    // don't autosave on aspit 1, 3 and 4 (the main menus)
    RXSimpleCardDescriptor* scd = [gameState currentCard];
    if (!scd)
        return;
    if ([scd->stackKey isEqualToString:@"aspit"] && (scd->cardID == 1 || scd->cardID == 3 || scd->cardID == 4))
        return;
    
    // FIXME: the autosave should contain extra data to point to the actual saved game such that if we load the autosave,
    // saving will continue to go in the actual saved game
    [gameState writeToURL:autosaveURL updateURL:NO error:NULL];
}

- (BOOL)isGameLoaded
{
    return (g_world) ? [[RXWorld sharedWorld] isInstalled] : NO;
}

- (BOOL)isGameLoadingAndSavingDisabled
{
    return disableGameSavingAndLoading || ![self isGameLoaded];
}

- (void)setDisableGameLoadingAndSaving:(BOOL)disable
{
    disableGameSavingAndLoading = disable;
    if (missedAutosave)
        [self _autosave:nil];
}

@end
