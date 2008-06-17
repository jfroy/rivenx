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

- (BOOL)canSave {
	return _canSave;
}

- (void)setCanSave:(BOOL)flag {
	_canSave = flag;
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
	
}

- (IBAction)saveGame:(id)sender {
	
}

- (IBAction)saveGameAs:(id)sender {
	
}

@end
