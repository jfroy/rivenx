/*
 *	RXDebug.m
 *	rivenx
 *
 *	Created by Jean-François Roy on 10/04/2007.
 *	Copyright 2007 MacStorm. All rights reserved.
 *
 */

void rx_print_exception_backtrace(NSException* e) {
	NSArray* stack = [[[e userInfo] objectForKey:NSStackTraceKey] componentsSeparatedByString:@"  "];
	if (!stack && [e respondsToSelector:@selector(callStackReturnAddresses)]) stack = [e callStackReturnAddresses];
	
	if (stack) {
		// sometimes, the value 0x1 makes its way as the last call stack return address; ignore it
		if ([[stack lastObject] isKindOfClass:[NSString class]]) {
			NSScanner* scanner = [[NSScanner alloc] initWithString:[stack lastObject]];
			uint32_t address;
			[scanner scanHexInt:&address];
			if (address == 0x1)
				stack = [stack subarrayWithRange:NSMakeRange(0, [stack count] - 1)];
		}
		
		NSTask* ls = [[NSTask alloc] init];
		NSString* pid = [[NSNumber numberWithInt:getpid()] stringValue];
		NSMutableArray* args = [NSMutableArray arrayWithCapacity:20];
		
		[args addObject:@"-p"];
		[args addObject:pid];
		[args addObjectsFromArray:stack];
		// Note: function addresses are separated by double spaces, not a single space.
		
		[ls setLaunchPath:@"/usr/bin/atos"];
		[ls setArguments:args];
		[ls launch];
		[ls release];
	} else RXLog(kRXLoggingBase, kRXLoggingLevelCritical, @"NO BACKTRACE AVAILABLE");
}
