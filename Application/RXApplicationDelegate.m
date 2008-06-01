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
	[aboutBox_ center];
	
	NSBundle* mainBundle = [NSBundle mainBundle];
	NSString* versionFormat = NSLocalizedStringFromTable(@"VERSION_FORMAT", @"About", nil);
	[versionField_ setStringValue:[NSString stringWithFormat:versionFormat, [mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"], [mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]]];
	[copyrightField_ setStringValue:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSHumanReadableCopyright"]];
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
}

- (void)windowWillClose:(NSNotification *)aNotification {
	[NSApp terminate:self];
}

- (void)applicationWillTerminate:(NSNotification *)notification {

}

- (IBAction)orderFrontAboutWindow:(id)sender {
	[aboutBox_ makeKeyAndOrderFront:sender];
}

- (IBAction)showAcknowledgments:(id)sender {
	NSString* ackPath = [[NSBundle mainBundle] pathForResource:@"Riven X Acknowledgments" ofType:@"pdf"];
	[[NSWorkspace sharedWorkspace] openFile:ackPath];
}

@end
