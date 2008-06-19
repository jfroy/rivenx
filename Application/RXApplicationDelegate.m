//
//	RXApplicationDelegate.m
//	rivenx
//
//	Created by Jean-Francois Roy on 30/08/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <ExceptionHandling/NSExceptionHandler.h>

#import "RXApplicationDelegate.h"
#import "RXWorld.h"
#import "RXEditionManagerWindowController.h"

#import "RXDebugWindowController.h"

@implementation RXApplicationDelegate

- (void)awakeFromNib {
	[_aboutBox center];
	
	NSBundle* mainBundle = [NSBundle mainBundle];
	NSString* versionFormat = NSLocalizedStringFromTable(@"VERSION_FORMAT", @"About", nil);
	[_versionField setStringValue:[NSString stringWithFormat:versionFormat, [mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"], [mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]]];
	[_copyrightField setStringValue:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSHumanReadableCopyright"]];
}

#if defined(DEBUG)
- (void)_showDebugConsole:(id)sender {
	[_debugConsoleWC showWindow:sender];
}

- (void)_initDebugUI {
	_debugConsoleWC = [[RXDebugWindowController alloc] initWithWindowNibName:@"DebugConsole"];
	
	NSMenu* debugMenu = [[NSMenu alloc] initWithTitle:@"Debug"];
	[debugMenu addItemWithTitle:@"Console" action:@selector(_showDebugConsole:) keyEquivalent:@""];
	
	NSMenuItem* debugMenuItem = [[NSMenuItem alloc] initWithTitle:@"Debug" action:NULL keyEquivalent:@""];
	[debugMenuItem setSubmenu:debugMenu];
	[[NSApp mainMenu] addItem:debugMenuItem];
	
	[debugMenu release];
	[debugMenuItem release];
}
#endif

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

- (BOOL)exceptionHandler:(NSExceptionHandler *)sender shouldLogException:(NSException *)exception mask:(NSUInteger)aMask {
	rx_print_exception_backtrace(exception);
	return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
#if defined(DEBUG)
	[[NSExceptionHandler defaultExceptionHandler] setDelegate:self];
	[[NSExceptionHandler defaultExceptionHandler] setExceptionHandlingMask:NSLogUncaughtExceptionMask | NSLogUncaughtSystemExceptionMask | NSLogUncaughtRuntimeErrorMask | NSLogTopLevelExceptionMask | NSLogOtherExceptionMask];
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
	if (result == NSCancelButton) return;
	
	NSError* error;
	RXGameState* gameState = [RXGameState gameStateWithURL:[panel URL] error:&error];
	if (!gameState) {
		[NSApp presentError:error];
		return;
	}
	
	if (![[RXWorld sharedWorld] loadGameState:gameState error:&error]) [NSApp presentError:error];
}

- (IBAction)saveGame:(id)sender {
	NSError* error;
	RXGameState* gameState = [g_world gameState];
	if (![gameState writeToURL:[gameState URL] error:&error]) [NSApp presentError:error];
}

- (void)_saveAsPanelDidEnd:(NSSavePanel*)panel returnCode:(int)returnCode contextInfo:(void*)contextInfo {
	if (returnCode == NSCancelButton) return;
	
	NSError* error = nil;
	RXGameState* gameState = [g_world gameState];
	if (![gameState writeToURL:[panel URL] error:&error]) [NSApp presentError:error];
	else [self _updateCanSave];
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
