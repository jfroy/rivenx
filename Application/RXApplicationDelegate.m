//
//	RXApplicationDelegate.m
//	rivenx
//
//	Created by Jean-Francois Roy on 30/08/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import "RXApplicationDelegate.h"

#import <ExceptionHandling/NSExceptionHandler.h>

#import <Sparkle/SUUpdater.h>

#import "Engine/RXWorld.h"
#import "Engine/RXEditionManagerWindowController.h"

#import "Rendering/Graphics/RXWorldView.h"

#import "Debug/RXDebugWindowController.h"
//#import "Debug/RXCardInspectorController.h"

#import "Utilities/GTMSystemVersion.h"


@interface RXApplicationDelegate (RXApplicationDelegate_Private)
- (BOOL)_openGameWithURL:(NSURL*)url;
@end

@implementation RXApplicationDelegate

+ (void)initialize {
	[super initialize];
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO], @"FullScreenMode", [NSNumber numberWithBool:NO], @"StretchToFit", nil]];
}

- (void)awakeFromNib {
	[_aboutBox center];
	[_preferences center];
	
	NSBundle* mainBundle = [NSBundle mainBundle];
	NSString* versionFormat = NSLocalizedStringFromTable(@"VERSION_FORMAT", @"About", nil);
	[_versionField setStringValue:[NSString stringWithFormat:versionFormat, [mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"], [mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]]];
	[_copyrightField setStringValue:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSHumanReadableCopyright"]];
	
	_fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"FullScreenMode"];
}

- (void)dealloc {
	[super dealloc];
}

#pragma mark -
#pragma mark debug UI

#if defined(DEBUG)
- (void)_showDebugConsole:(id)sender {
	[_debugConsoleWC showWindow:sender];
}

- (void)_showCardInspector:(id)sender {
//	if (!_card_inspector_controller)
//		_card_inspector_controller = [[RXCardInspectorController alloc] initWithWindowNibName:@"CardInspector"];
//	[_card_inspector_controller showWindow:sender];
}

- (void)_initDebugUI {
	_debugConsoleWC = [[RXDebugWindowController alloc] initWithWindowNibName:@"DebugConsole"];
	
	NSMenu* debugMenu = [[NSMenu alloc] initWithTitle:@"Debug"];
	[debugMenu addItemWithTitle:@"Console" action:@selector(_showDebugConsole:) keyEquivalent:@""];
//	[debugMenu addItemWithTitle:@"Card Inspector" action:@selector(_showCardInspector:) keyEquivalent:@""];
	
	NSMenuItem* debugMenuItem = [[NSMenuItem alloc] initWithTitle:@"Debug" action:NULL keyEquivalent:@""];
	[debugMenuItem setSubmenu:debugMenu];
	[[NSApp mainMenu] addItem:debugMenuItem];
	
	[debugMenu release];
	[debugMenuItem release];
}
#endif

#pragma mark -
#pragma mark error handling

- (BOOL)attemptRecoveryFromError:(NSError*)error optionIndex:(NSUInteger)recoveryOptionIndex {
	if ([error domain] == RXErrorDomain) {
		switch ([error code]) {
			case kRXErrEditionCantBecomeCurrent:
				if (recoveryOptionIndex == 0)
					[[RXEditionManager sharedEditionManager] showEditionManagerWindow];
				else
					[NSApp terminate:self];
				break;
			case kRXErrSavedGameCantBeLoaded:
				if (recoveryOptionIndex == 0)
					[[RXEditionManager sharedEditionManager] showEditionManagerWindow];
				break;
			case kRXErrArchiveUnavailable:
				// this is fatal right now
				[NSApp terminate:self];
				break;
		}
		return YES;
	}
	
	return NO;
}

- (void)notifyUserOfFatalException:(NSException*)e {
	NSError* error = [[e userInfo] objectForKey:NSUnderlyingErrorKey];
	
	[[NSExceptionHandler defaultExceptionHandler] setExceptionHandlingMask:0];
	rx_print_exception_backtrace(e);
	[[NSExceptionHandler defaultExceptionHandler] setExceptionHandlingMask:NSLogAndHandleEveryExceptionMask];

	NSAlert* failureAlert = [NSAlert new];
	[failureAlert setMessageText:[e reason]];
	[failureAlert setAlertStyle:NSWarningAlertStyle];
	[failureAlert addButtonWithTitle:NSLocalizedString(@"Quit", @"quit button")];
	
	NSDictionary* userInfo = [e userInfo];
	if (userInfo) {
		if (error)
			[failureAlert setInformativeText:[error localizedDescription]];
		else
			[failureAlert setInformativeText:[e name]];
	} else
		[failureAlert setInformativeText:[e name]];
	
	[failureAlert runModal];
	[failureAlert release];
	
	[NSApp terminate:nil];
}

- (BOOL)exceptionHandler:(NSExceptionHandler*)sender shouldLogException:(NSException*)e mask:(NSUInteger)aMask {
	if ([[e name] isEqualToString:@"RXCommandArgumentsException"] || [[e name] isEqualToString:@"RXUnknownCommandException"] || [[e name] isEqualToString:@"RXCommandError"])
		return NO;
	
	[self notifyUserOfFatalException:e];
	return NO;
}

#pragma mark -
#pragma mark delegation and UI

- (void)applicationWillFinishLaunching:(NSNotification*)notification {
	[[NSExceptionHandler defaultExceptionHandler] setDelegate:self];
	[[NSExceptionHandler defaultExceptionHandler] setExceptionHandlingMask:NSLogAndHandleEveryExceptionMask];
	
	// and a flower shall blossom
	[RXWorld sharedWorld];
	
#if defined(DEBUG)
	[self _initDebugUI];
	[self _showDebugConsole:self];
#endif
}

- (void)applicationWillTerminate:(NSNotification *)notification {
	
}

- (BOOL)application:(NSApplication*)theApplication openFile:(NSString*)filename {
	return [self _openGameWithURL:[NSURL fileURLWithPath:filename]];
}

- (void)windowWillClose:(NSNotification *)aNotification {
	[NSApp terminate:self];
}

- (id <SUVersionComparison>)versionComparatorForUpdater:(SUUpdater*)updater {
	return versionComparator;
}

- (IBAction)orderFrontAboutWindow:(id)sender {
	[_aboutBox makeKeyAndOrderFront:sender];
}

- (IBAction)showAcknowledgments:(id)sender {
	NSString* ackPath = [[NSBundle mainBundle] pathForResource:@"Riven X Acknowledgments" ofType:@"pdf"];
	[[NSWorkspace sharedWorkspace] openFile:ackPath];
}

- (IBAction)showPreferences:(id)sender {
	[_preferences makeKeyAndOrderFront:sender];
	if (_fullscreen)
		[_preferences setLevel:NSTornOffMenuWindowLevel];
}

- (IBAction)toggleFullscreen:(id)sender {
	// FIXME: implement method in RXRendering or RXWorld (in RXWorldRendering.mm) to do this
}

- (IBAction)toggleStretchToFit:(id)sender {
	BOOL stretchToFit = [[NSUserDefaults standardUserDefaults] boolForKey:@"StretchToFit"];
	[[NSUserDefaults standardUserDefaults] setBool:!stretchToFit forKey:@"StretchToFit"];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:@"RXOpenGLDidReshapeNotification" object:self];
}

- (IBAction)openDocument:(id)sender {
	NSOpenPanel* panel = [NSOpenPanel openPanel];
	[panel setCanChooseFiles:YES];
	[panel setCanChooseDirectories:NO];
	[panel setAllowsMultipleSelection:NO];
	
	[panel setCanCreateDirectories:YES];
	[panel setAllowsOtherFileTypes:NO];
	[panel setCanSelectHiddenExtension:YES];
	[panel setTreatsFilePackagesAsDirectories:NO];
	
	NSArray* types;
	if ([GTMSystemVersion isLeopardOrGreater])
		types = [NSArray arrayWithObject:@"org.macstorm.rivenx.game"];
	else
		types = [NSArray arrayWithObject:[(NSString*)UTTypeCopyPreferredTagWithClass(CFSTR("org.macstorm.rivenx.game"), kUTTagClassFilenameExtension) autorelease]];
	NSInteger result = [panel runModalForDirectory:nil file:nil types:types];
	if (result == NSCancelButton)
		return;
	
	[self _openGameWithURL:[panel URL]];
}

- (IBAction)saveGame:(id)sender {
	NSError* error;
	RXGameState* gameState = [g_world gameState];
	if (![gameState writeToURL:[gameState URL] error:&error])
		[NSApp presentError:error];
}

- (IBAction)saveGameAs:(id)sender {
	NSSavePanel* panel = [NSSavePanel savePanel];
	[panel setCanCreateDirectories:YES];
	[panel setAllowsOtherFileTypes:NO];
	[panel setCanSelectHiddenExtension:YES];
	[panel setTreatsFilePackagesAsDirectories:NO];
	
	NSArray* types;
	if ([GTMSystemVersion isLeopardOrGreater])
		types = [NSArray arrayWithObject:@"org.macstorm.rivenx.game"];
	else
		types = [NSArray arrayWithObject:[(NSString*)UTTypeCopyPreferredTagWithClass(CFSTR("org.macstorm.rivenx.game"), kUTTagClassFilenameExtension) autorelease]];
	[panel setAllowedFileTypes:types];
	
	[panel beginSheetForDirectory:nil file:@"untitled" modalForWindow:[g_worldView window] modalDelegate:self didEndSelector:@selector(_saveAsPanelDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

#pragma mark -
#pragma mark game opening and saving

- (BOOL)_openGameWithURL:(NSURL*)url {
	NSError* error;
	
	// load the save file, and present any error to the user if one occurs
	RXGameState* gameState = [RXGameState gameStateWithURL:url error:&error];
	if (!gameState) {
		[NSApp presentError:error];
		return NO;
	}
	
	// the save game may be using a different edition than the active edition
	if (![[gameState edition] isEqual:[[RXEditionManager sharedEditionManager] currentEdition]]) {
		// check if the game's edition can be made current; if not, present an error to the user
		if (![[gameState edition] canBecomeCurrent]) {
			error = [NSError errorWithDomain:RXErrorDomain code:kRXErrSavedGameCantBeLoaded userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
				[NSString stringWithFormat:@"Riven X cannot load the saved game because \"%@\" is not installed.", [[gameState edition] valueForKey:@"name"]], NSLocalizedDescriptionKey,
				@"You may install this edition by using the Edition Manager, or cancel and resume your current game.", NSLocalizedRecoverySuggestionErrorKey,
				[NSArray arrayWithObjects:@"Install", @"Cancel", nil], NSLocalizedRecoveryOptionsErrorKey,
				self, NSRecoveryAttempterErrorKey,
				nil]];
			[NSApp presentError:error];
			return NO;
		}
	}
	
	// try to load the game, and present any error to the user if one occurs
	if (![[RXWorld sharedWorld] loadGameState:gameState error:&error]) {
		[NSApp presentError:error];
		return NO;
	}
	
	// add the save file to the recents
	[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[gameState URL]];
	
	return YES;
}

- (void)_updateCanSave {
	[self willChangeValueForKey:@"canSave"];
	_canSave = (([[g_world gameState] URL])) ? YES : NO;
	[self didChangeValueForKey:@"canSave"];
}

- (BOOL)isSavingEnabled {
	return _saveFlag;
}

- (void)setSavingEnabled:(BOOL)flag {
	_saveFlag = flag;
	[self _updateCanSave];
}

- (BOOL)isFullscreen {
	return _fullscreen;
}

- (void)_saveAsPanelDidEnd:(NSSavePanel*)panel returnCode:(int)returnCode contextInfo:(void*)contextInfo {
	if (returnCode == NSCancelButton)
		return;
	
	// dismiss the panel now
	[panel orderOut:self];
	
	NSError* error = nil;
	RXGameState* gameState = [g_world gameState];
	if (![gameState writeToURL:[panel URL] error:&error]) {
		[NSApp presentError:error];
		return;
	}
	
	// we need to update the can-save state now, since we may not have had a save file before we saved as
	[self _updateCanSave];
	
	// add the new save file to the recents
	[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[gameState URL]];	
}

@end
