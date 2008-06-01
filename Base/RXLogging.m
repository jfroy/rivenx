/*
 *  RXLogging.m
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 26/02/2008.
 *  Copyright 2008 MacStorm. All rights reserved.
 *
 */

#import <asl.h>

#import "RXLogging.h"
#import "RXLogCenter.h"
#import "RXThreadUtilities.h"

/* facilities */
const char* kRXLoggingBase = "BASE";
const char* kRXLoggingEngine = "ENGINE";
const char* kRXLoggingRendering = "RENDERING";
const char* kRXLoggingScript = "SCRIPT";
const char* kRXLoggingGraphics = "GRAPHICS";
const char* kRXLoggingAudio = "AUDIO";
const char* kRXLoggingEvents = "EVENTS";

/* levels */
const int kRXLoggingLevelDebug = ASL_LEVEL_DEBUG;
const int kRXLoggingLevelMessage = ASL_LEVEL_NOTICE;
const int kRXLoggingLevelError = ASL_LEVEL_ERR;
const int kRXLoggingLevelCritical = ASL_LEVEL_CRIT;

static NSString* RX_log_format = @"[%@] [%@] [%@] %@\n";

void RXLog(const char* facility, int level, NSString* format, ...) {
	va_list args;
	va_start(args, format);
	RXLogv(facility, level, format, args);
	va_end(args);
}

void RXLogv(const char* facility, int level, NSString* format, va_list args) {
	NSString* userString = [[NSString alloc] initWithFormat:format arguments:args];
	NSString* facilityString = [[NSString alloc] initWithCString:facility encoding:NSASCIIStringEncoding];
	NSDate* now = [NSDate new];
	
	NSString* threadName = RXGetThreadName();
	if (!threadName) threadName = @"unknown thread";
	
	NSString* logString = [[NSString alloc] initWithFormat:RX_log_format, now, threadName, facilityString, userString];
	[[RXLogCenter sharedLogCenter] log:logString facility:facilityString level:level];
	
	[logString release];
	[now release];
	[facilityString release];
	[userString release];
}

void _RXOLog(id object, const char* facility, int level, NSString* format, ...) {
	va_list args;
	va_start(args, format);
	
	NSString* finalFormat = [[NSString alloc] initWithFormat:@"%@: %@", [object description], format];
	RXLogv(facility, level, finalFormat, args);
	
	va_end(args);
	[finalFormat release];
}

void RXCFLog(const char* facility, int level, CFStringRef format, ...) {
	va_list args;
	va_start(args, format);
	RXLogv(facility, level, (NSString*)format, args);
	va_end(args);
}
