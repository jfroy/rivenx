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

- (IBAction)showWindow:(id)sender {
	if ([self isWindowLoaded])
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_activeCardDidChange:) name:@"RXActiveCardDidChange" object:nil];
	[super showWindow:sender];
}

- (void)windowDidLoad {
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_activeCardDidChange:) name:@"RXActiveCardDidChange" object:nil];
}

- (void)windowWillClose:(NSNotification*)notification {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"RXActiveCardDidChange" object:nil];
}

- (void)_activeCardDidChange:(NSNotification*)notification {
	RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"active card did change received by card inspector");
	id card = [notification object];
	[_cardContentView setContent:[card valueForKey:@"movies"]];
}

@end
