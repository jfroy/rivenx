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

- (NSString*)windowFrameAutosaveName {
	return @"DebugWindowFrame";
}

- (void)help:(NSArray*)arguments from:(CLIView*)sender {
	[sender putText:@"you're on your own, sorry"];
}

- (void)cmd_card:(NSArray*)arguments from:(CLIView*)sender {
	if ([arguments count] < 2)
		@throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"card [stack] [ID]" userInfo:nil];

	RXCardState* renderingState = (RXCardState*)[g_world cardRenderState];

	NSString* stackKey = [arguments objectAtIndex:0];
	NSString* cardStringID = [arguments objectAtIndex:1];

	int cardID;
	BOOL foundID = [[NSScanner scannerWithString:cardStringID] scanInt:&cardID];
	if (!foundID)
		@throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"card [stack] [ID]" userInfo:nil];

	RXOLog2(kRXLoggingBase, kRXLoggingLevelDebug, @"changing active card to %@:%d", stackKey, cardID);
	[renderingState setActiveCardWithStack:stackKey ID:cardID waitUntilDone:NO];
}

- (void)cmd_refresh:(NSArray*)arguments from:(CLIView*)sender {
	RXSimpleCardDescriptor* current_card = [[g_world gameState] currentCard];
	RXCardState* renderingState = (RXCardState*)[g_world cardRenderState];
	[renderingState setActiveCardWithStack:current_card->stackKey ID:current_card->cardID waitUntilDone:NO];
}

- (void)_activateSLST:(NSNumber*)index {
	RXCardState* renderingState = (RXCardState*)[g_world cardRenderState];
	uint16_t args = (uint16_t)[index intValue];
	[[renderingState valueForKey:@"sengine"] performSelector:@selector(_opcode_activateSLST:arguments:) withObject:(id)1 withObject:(id)&args];
}

- (void)cmd_slst:(NSArray*)arguments from:(CLIView*)sender {
	if ([arguments count] < 1)
		@throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"slst [1-based index]" userInfo:nil];
	[self performSelector:@selector(_activateSLST:) withObject:[arguments objectAtIndex:0] inThread:[g_world scriptThread] waitUntilDone:YES];
}

- (void)cmd_get:(NSArray*)arguments from:(CLIView*)sender {
	if ([arguments count] < 1)
		@throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"get [variable]" userInfo:nil];
	NSString* path = [arguments objectAtIndex:1];
	
	if ([[g_world gameState] isKeySet:path])
		[sender putText:[NSString stringWithFormat:@"%d\n", [[g_world gameState] signed32ForKey:path]]];
	else
		[sender putText:[NSString stringWithFormat:@"%@\n", [[g_world valueForKeyPath:path] stringValue]]];
}

- (void)cmd_set:(NSArray*)arguments from:(CLIView*)sender {
	if ([arguments count] < 2)
		@throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"set [variable] [value]" userInfo:nil];
	
	NSString* path = [arguments objectAtIndex:0];
	NSString* valueString = [arguments objectAtIndex:1];
	NSScanner* valueScanner = [NSScanner scannerWithString:valueString];
	id value;
	
	// scan away
	BOOL valueFound = NO;
	double doubleValue;
	int intValue;
	
	valueFound = [valueScanner scanDouble:&doubleValue];
	if (valueFound)
		value = [NSNumber numberWithDouble:doubleValue];
	else {
		valueFound = [valueScanner scanInt:&intValue];
		if (valueFound)
			value = [NSNumber numberWithInt:intValue];
		else {
			if ([valueString isEqualToString:@"yes"] || [valueString isEqualToString:@"YES"])
				valueFound = YES;
			
			if (valueFound)
				value = [NSNumber numberWithBool:YES];
			else {
				if ([valueString isEqualToString:@"no"] || [valueString isEqualToString:@"NO"])
					valueFound = YES;
				
				if (valueFound)
					value = [NSNumber numberWithBool:NO];
				else
					value = valueString;
			}
		}
	}
	
	if ([[g_world gameState] isKeySet:path]) {
		if (![value isKindOfClass:[NSNumber class]])
			@throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"game variables can only be set to integer values" userInfo:nil];
		else {
			[[g_world gameState] setSigned32:[value intValue] forKey:path];
		}
	} else
		[g_world setValue:value forKeyPath:path];
}

- (void)cmd_dump:(NSArray*)arguments from:(CLIView*)sender {
	if ([arguments count] < 1)
		@throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"dump [game | engine]" userInfo:nil];
	
	if ([[arguments objectAtIndex:0] isEqualToString:@"game"])
		[[g_world gameState] dump];
	else if ([[arguments objectAtIndex:0] isEqualToString:@"engine"])
		[g_world performSelector:@selector(_dumpEngineVariables)];
	else
		@throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"dump [game | engine]" userInfo:nil];
}

- (void)_nextJspitCard:(NSNotification*)notification {
	_trip++;
	if (_trip > 800) {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:@"RXActiveCardDidChange" object:nil];
		return;
	}
	
	RXStack* jspit = [g_world activeStackWithKey:@"jspit"];
	RXCardDescriptor* d = [RXCardDescriptor descriptorWithStack:jspit ID:_trip];
	while (!d) {
		_trip++;
		d = [RXCardDescriptor descriptorWithStack:jspit ID:_trip];
	}
	
	RXCardState* renderingState = (RXCardState *)[g_world cardRenderState];
	[renderingState setActiveCardWithStack:@"jspit" ID:_trip waitUntilDone:NO];
}

- (void)cmd_jtrip:(NSArray*)arguments from:(CLIView*)sender {
	RXCardState* renderingState = (RXCardState*)[g_world cardRenderState];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_nextJspitCard:) name:@"RXActiveCardDidChange" object:nil];
	_trip = 1;
	[renderingState setActiveCardWithStack:@"jspit" ID:_trip waitUntilDone:NO];
}

- (void)command:(NSString*)command from:(CLIView*)sender {
	if ([command length] == 0)
		return;
	
	NSArray* components = [command componentsSeparatedByString:@" "];
	NSString* command_name = [components objectAtIndex:0];
	components = [components subarrayWithRange:NSMakeRange(1, [components count] - 1)];
	
	@try {
		SEL commandSel = NSSelectorFromString([NSString stringWithFormat:@"cmd_%@:from:", command_name]);
		if ([self respondsToSelector:commandSel])
			[self performSelector:commandSel withObject:components withObject:sender];
		else
			@throw [NSException exceptionWithName:@"RXUnknownCommandException" reason:@"Command not found, type help for commands." userInfo:nil];
	} @catch (NSException* e) {
		NSString* exceptionName = [e name];
		if ([exceptionName isEqualToString:@"RXCommandArgumentsException"]) {
			[sender putText:[NSString stringWithFormat:@"usage: %@\n", [e reason]]];
		} else if ([exceptionName isEqualToString:@"RXUnknownCommandException"]) {
			[sender putText:[NSString stringWithFormat:@"%@: command not found\n", command_name]];
		} else if ([exceptionName isEqualToString:@"RXCommandError"]) {
			[sender putText:[e reason]];
			[sender putText:@"\n"];
		} else {
			[sender putText:[NSString stringWithFormat:@"unknown error: %@ - %@\n", [e name], [e reason]]];
		}
	}
}

@end
