//
//	RXDebugWindowController.m
//	rivenx
//
//	Created by Jean-Francois Roy on 27/01/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import "RXDebugWindowController.h"
#import "RXWorldProtocol.h"

#import "RXCardState.h"

@interface NSObject (CLIViewPrivate)
- (void)notifyUser:(NSString *)message;
- (void)putText:(NSString *)text;
@end

@implementation RXDebugWindowController

- (void)awakeFromNib {
	[self setWindowFrameAutosaveName:@"Debug Window"];
	[cli notifyUser:@"Riven X debug shell v3. Type help for commands. Type a command for usage information."];
}

- (void)help:(NSArray*)commandComponents from:(CLIView*)sender {
	if ([commandComponents count] == 1) [sender putText:@"built-in commands:\n\n	help\n	  card\n	list\n	  load\n"];
	else {
		NSString* primaryCommandHelp = [[commandComponents objectAtIndex:1] stringByAppendingString:@"Help"];
		SEL commandSel = NSSelectorFromString(primaryCommandHelp);
		if ([self respondsToSelector:commandSel]) [self performSelector:commandSel];
		else [sender putText:[NSString stringWithFormat:@"no help is avaiable for command", [commandComponents objectAtIndex:1]]];
	}
}

- (void)card:(NSArray*)commandComponents from:(CLIView*)sender {
	if ([commandComponents count] < 3) @throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"card [stack] [ID]" userInfo:nil];

	RXCardState* renderingState = (RXCardState *)[g_world cardRenderState];

	NSString* stackKey = [commandComponents objectAtIndex:1];
	NSString* cardStringID = [commandComponents objectAtIndex:2];

	int cardID;
	BOOL foundID = [[NSScanner scannerWithString:cardStringID] scanInt:&cardID];
	if (!foundID) @throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"card [stack] [ID]" userInfo:nil];

	RXOLog2(kRXLoggingBase, kRXLoggingLevelDebug, @"changing active card to %@:%d", stackKey, cardID);
	[renderingState setActiveCardWithStack:stackKey ID:cardID waitUntilDone:NO];
}

- (void)set:(NSArray*)commandComponents from:(CLIView*)sender {
	if ([commandComponents count] < 3) @throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"set [variable] [value]" userInfo:nil];
	
	NSString* path = [commandComponents objectAtIndex:1];
	NSString* valueString = [commandComponents objectAtIndex:2];
	NSScanner* valueScanner = [NSScanner scannerWithString:valueString];
	id value;
	
	// scan away
	BOOL valueFound = NO;
	double doubleValue;
	int intValue;
	
	valueFound = [valueScanner scanDouble:&doubleValue];
	if (valueFound) value = [NSNumber numberWithDouble:doubleValue];
	else {
		valueFound = [valueScanner scanInt:&intValue];
		if (valueFound) value = [NSNumber numberWithInt:intValue];
		else {
			if ([valueString isEqualToString:@"yes"] || [valueString isEqualToString:@"YES"]) valueFound = YES;
			if (valueFound) value = [NSNumber numberWithBool:YES];
			else {
				if ([valueString isEqualToString:@"no"] || [valueString isEqualToString:@"NO"]) valueFound = YES;
				if (valueFound) value = [NSNumber numberWithBool:NO];
				else value = valueString;
			}
		}
	}
	
	if ([[g_world gameState] isKeySet:path]) {
		if (![value isKindOfClass:[NSNumber class]]) @throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"game variables can only be set to integer values" userInfo:nil];
		else [[g_world gameState] setShort:[value shortValue] forKey:path];
	} else [g_world setValue:value forKeyPath:path];
}

- (void)dump:(NSArray*)commandComponents from:(CLIView*)sender {
	if ([commandComponents count] < 2) @throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"dump [game | engine]" userInfo:nil];
	
	if ([[commandComponents objectAtIndex:1] isEqualToString:@"game"]) [[g_world gameState] dump];
	else if ([[commandComponents objectAtIndex:1] isEqualToString:@"engine"]) [g_world performSelector:@selector(_dumpEngineVariables)];
	else @throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"dump [game | engine]" userInfo:nil];
}

- (void)_nextJspitCard:(NSNotification*)notification {
	_trip++;
	if (_trip > 800) return;
	
	RXStack* jspit = [g_world activeStackWithKey:@"jspit"];
	RXCardDescriptor* d = [RXCardDescriptor descriptorWithStack:jspit ID:_trip];
	while (!d) {
		_trip++;
		d = [RXCardDescriptor descriptorWithStack:jspit ID:_trip];
	}
	
	RXCardState* renderingState = (RXCardState *)[g_world cardRenderState];
	[renderingState setActiveCardWithStack:@"jspit" ID:_trip waitUntilDone:NO];
}

- (void)jtrip:(NSArray*)commandComponents from:(CLIView*)sender {
	RXCardState* renderingState = (RXCardState *)[g_world cardRenderState];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_nextJspitCard:) name:@"RXActiveCardDidChange" object:nil];
	_trip = 1;
	[renderingState setActiveCardWithStack:@"jspit" ID:_trip waitUntilDone:NO];
}

- (void)command:(NSString *)command from:(CLIView*)sender {
	if ([command length] == 0) return;
	
	NSArray* commandComponents = [command componentsSeparatedByString:@" "];
	NSString* primaryCommand = [[commandComponents objectAtIndex:0] stringByAppendingString:@":from:"];
	
	@try {
		SEL commandSel = NSSelectorFromString(primaryCommand);
		if ([self respondsToSelector:commandSel]) [self performSelector:commandSel withObject:commandComponents withObject:sender];
		else @throw [NSException exceptionWithName:@"RXUnknownCommandException" reason:@"Command not found, type help for commands." userInfo:nil];
	} @catch (NSException* e) {
		NSString* exceptionName = [e name];
		if ([exceptionName isEqualToString:@"RXCommandArgumentsException"]) {
			[sender putText:[NSString stringWithFormat:@"usage: %@\n", [e reason]]];
		} else if ([exceptionName isEqualToString:@"RXUnknownCommandException"]) {
			[sender putText:[NSString stringWithFormat:@"%@: command not found\n", primaryCommand]];
		} else if ([exceptionName isEqualToString:@"RXCommandError"]) {
			[sender putText:[e reason]];
			[sender putText:@"\n"];
		} else {
			[sender putText:[NSString stringWithFormat:@"unknown error: %@ - %@\n", [e name], [e reason]]];
		}
	}
}

@end
