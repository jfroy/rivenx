//
//  RXCardInspectorController.m
//  rivenx
//
//  Created by Jean-Francois Roy on 23/01/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import "RXCardInspectorController.h"


@implementation RXCardInspectorController

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (NSString*)windowFrameAutosaveName {
	return @"card inspector";
}

- (IBAction)showWindow:(id)sender {
	if ([self isWindowLoaded])
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_activeCardDidChange:) name:@"RXActiveCardDidChange" object:nil];
	[super showWindow:sender];
}

- (void)windowDidLoad {
	[_cardContentView setMinItemSize:NSMakeSize(100.0f, 100.0f)];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_activeCardDidChange:) name:@"RXActiveCardDidChange" object:nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"RXBroadcastCurrentCardNotification" object:nil];
}

- (void)windowWillClose:(NSNotification*)notification {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"RXActiveCardDidChange" object:nil];
}

- (void)_updateInspectorWithCard:(id)card {
	[_cardContentView setContent:[card valueForKey:@"movies"]];
}

- (void)_activeCardDidChange:(NSNotification*)notification {
	RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"active card did change received by card inspector");
	[self _updateInspectorWithCard:[notification object]];
}

@end
