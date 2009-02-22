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

#import "RXWorld.h"
#import "RXWorldView.h"
#import "RXEditionManagerWindowController.h"

#import "Debug/RXDebugWindowController.h"
#import "Debug/RXCardInspectorController.h"

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

#if defined(DEBUG)
- (void)_showDebugConsole:(id)sender {
	[_debugConsoleWC showWindow:sender];
}

- (void)_showCardInspector:(id)sender {
	if (!_card_inspector_controller)
		_card_inspector_controller = [[RXCardInspectorController alloc] initWithWindowNibName:@"CardInspector"];
	[_card_inspector_controller showWindow:sender];
}

- (void)_initDebugUI {
	_debugConsoleWC = [[RXDebugWindowController alloc] initWithWindowNibName:@"DebugConsole"];
	
	NSMenu* debugMenu = [[NSMenu alloc] initWithTitle:@"Debug"];
	[debugMenu addItemWithTitle:@"Console" action:@selector(_showDebugConsole:) keyEquivalent:@""];
	[debugMenu addItemWithTitle:@"Card Inspector" action:@selector(_showCardInspector:) keyEquivalent:@""];
	
	NSMenuItem* debugMenuItem = [[NSMenuItem alloc] initWithTitle:@"Debug" action:NULL keyEquivalent:@""];
	[debugMenuItem setSubmenu:debugMenu];
	[[NSApp mainMenu] addItem:debugMenuItem];
	
	[debugMenu release];
	[debugMenuItem release];
}
#endif

- (id <SUVersionComparison>)versionComparatorForUpdater:(SUUpdater*)updater {
	return versionComparator;
}

- (BOOL)exceptionHandler:(NSExceptionHandler*)sender shouldLogException:(NSException*)e mask:(NSUInteger)aMask {
#if defined(DEBUG)
	[[NSExceptionHandler defaultExceptionHandler] setExceptionHandlingMask:0];
#endif

	NSError* error = [[e userInfo] objectForKey:NSUnderlyingErrorKey];
	if (error)
		RXLog(kRXLoggingBase, kRXLoggingLevelCritical, @"EXCEPTION THROWN: \"%@\", ERROR: \"%@\"", e, error);
	else
		RXLog(kRXLoggingBase, kRXLoggingLevelCritical, @"EXCEPTION THROWN: %@", e);
	rx_print_exception_backtrace(e);
	
#if defined(DEBUG)
	[[NSExceptionHandler defaultExceptionHandler] setExceptionHandlingMask:NSLogAndHandleEveryExceptionMask];
#endif
	
	return NO;
}

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification {
#if defined(DEBUG)
	[[NSExceptionHandler defaultExceptionHandler] setDelegate:self];
	[[NSExceptionHandler defaultExceptionHandler] setExceptionHandlingMask:NSLogAndHandleEveryExceptionMask];
#endif
	
	[RXWorld sharedWorld];
#if defined(DEBUG)
		[self _initDebugUI];
		[self _showDebugConsole:self];
#endif
	
//	int openDocumentMenuItemIndex = [fileMenu indexOfItemWithTarget:nil andAction:@selector(openDocument:)];
//	if (openDocumentMenuItemIndex >= 0 && [[fileMenu itemAtIndex:openDocumentMenuItemIndex+1] hasSubmenu]) {
//		// We'll presume it's the Open Recent menu item, because this is the heuristic that NSDocumentController uses to add it to the File menu
//		[fileMenu removeItemAtIndex:openDocumentMenuItemIndex+1];
//	}
}

- (void)windowWillClose:(NSNotification *)aNotification {
	[NSApp terminate:self];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
	
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

#pragma mark error recovery

- (BOOL)attemptRecoveryFromError:(NSError*)error optionIndex:(NSUInteger)recoveryOptionIndex {
	if ([error domain] == RXErrorDomain) {
		switch ([error code]) {
			case kRXErrEditionCantBecomeCurrent:
				if (recoveryOptionIndex == 0)
					[[RXEditionManager sharedEditionManager] showEditionManagerWindow];
				else
					[NSApp terminate:self];
				break;
			case kRXErrSaveCantBeLoaded:
				if (recoveryOptionIndex == 0)
					[[RXEditionManager sharedEditionManager] showEditionManagerWindow];
				break;
		}
		return YES;
	}
	
	return NO;
}

#pragma mark open and save menu UI

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

- (IBAction)toggleFullscreen:(id)sender {
	// FIXME: implement method in RXRendering or RXWorld (in RXWorldRendering.mm) to do this
}

- (IBAction)toggleStretchToFit:(id)sender {
	BOOL stretchToFit = [[NSUserDefaults standardUserDefaults] boolForKey:@"StretchToFit"];
	[[NSUserDefaults standardUserDefaults] setBool:!stretchToFit forKey:@"StretchToFit"];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:@"RXOpenGLDidReshapeNotification" object:self];
}

- (BOOL)isFullscreen {
	return _fullscreen;
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
	
	[panel setRequiredFileType:[(NSString*)UTTypeCopyPreferredTagWithClass(CFSTR("org.macstorm.rivenx.game"), kUTTagClassFilenameExtension) autorelease]];
	
	NSInteger result = [panel runModalForDirectory:nil file:nil types:[NSArray arrayWithObject:@"org.macstorm.rivenx.game"]];
	if (result == NSCancelButton)
		return;
	
	NSError* error;
	
	// load the save file, and present any error to the user if one occurs
	RXGameState* gameState = [RXGameState gameStateWithURL:[panel URL] error:&error];
	if (!gameState) {
		[NSApp presentError:error];
		return;
	}
	
	// the save game may be using a different edition than the active edition
	if (![[gameState edition] isEqual:[[RXEditionManager sharedEditionManager] currentEdition]]) {
		// check if the game's edition can be made current; if not, present an error to the user
		if (![[gameState edition] canBecomeCurrent]) {
			error = [NSError errorWithDomain:RXErrorDomain code:kRXErrSaveCantBeLoaded userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
				[NSString stringWithFormat:@"Riven X cannot load the saved game because \"%@\" is not installed.", [[gameState edition] valueForKey:@"name"]], NSLocalizedDescriptionKey,
				@"You may install this edition by using the Edition Manager, or cancel and resume your current game.", NSLocalizedRecoverySuggestionErrorKey,
				[NSArray arrayWithObjects:@"Install", @"Cancel", nil], NSLocalizedRecoveryOptionsErrorKey,
				self, NSRecoveryAttempterErrorKey,
				nil]];
			[NSApp presentError:error];
			return;
		}
	}
	
	// try to load the game, and present any error to the user if one occurs
	if (![[RXWorld sharedWorld] loadGameState:gameState error:&error]) {
		[NSApp presentError:error];
		return;
	}
	
	// add the save file to the recents
	[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[gameState URL]];
}

- (IBAction)saveGame:(id)sender {
	NSError* error;
	RXGameState* gameState = [g_world gameState];
	if (![gameState writeToURL:[gameState URL] error:&error])
		[NSApp presentError:error];
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

- (IBAction)saveGameAs:(id)sender {
	NSSavePanel* panel = [NSSavePanel savePanel];
	[panel setCanCreateDirectories:YES];
	[panel setAllowsOtherFileTypes:NO];
	[panel setCanSelectHiddenExtension:YES];
	[panel setTreatsFilePackagesAsDirectories:NO];
	
	[panel setRequiredFileType:[(NSString*)UTTypeCopyPreferredTagWithClass(CFSTR("org.macstorm.rivenx.game"), kUTTagClassFilenameExtension) autorelease]];
	
	[panel beginSheetForDirectory:nil file:@"untitled" modalForWindow:[g_worldView window] modalDelegate:self didEndSelector:@selector(_saveAsPanelDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

@end
