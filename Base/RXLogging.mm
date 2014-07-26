/*
 *  RXLogging.m
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 26/02/2008.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#import "RXLogging.h"

#import <asl.h>
#import <mutex>

#import "Base/RXThreadUtilities.h"
#import "Utilities/osspinlock.h"

/* facilities */
const char* kRXLoggingBase = "BASE";
const char* kRXLoggingEngine = "ENGINE";
const char* kRXLoggingRendering = "RENDERING";
const char* kRXLoggingScript = "SCRIPT";
const char* kRXLoggingGraphics = "GRAPHICS";
const char* kRXLoggingAudio = "AUDIO";
const char* kRXLoggingEvents = "EVENTS";
const char* kRXLoggingAnimation = "ANIMATION";

/* levels */
const int kRXLoggingLevelDebug = ASL_LEVEL_DEBUG;
const int kRXLoggingLevelMessage = ASL_LEVEL_NOTICE;
const int kRXLoggingLevelError = ASL_LEVEL_ERR;
const int kRXLoggingLevelCritical = ASL_LEVEL_CRIT;

static NSString* const RX_log_format = @"%@ [%s] [%@] %@\n";

static void LogWithASL(const char* message, int level)
{
  static rx::OSSpinlock mutex;
  static aslclient client;
  std::lock_guard<rx::OSSpinlock> lock(mutex);

  if (client == nullptr) {
    client = asl_open(nullptr, nullptr, ASL_OPT_NO_DELAY);
    asl_set_filter(client, ASL_FILTER_MASK_UPTO(ASL_LEVEL_ERR));
#if DEBUG
    asl_add_output_file(client, STDERR_FILENO, ASL_MSG_FMT_MSG, ASL_TIME_FMT_LCL, ASL_FILTER_MASK_UPTO(ASL_LEVEL_DEBUG), ASL_ENCODE_NONE);
#endif
  }

  char level_str[4];
  snprintf(level_str, sizeof(level_str), "%d", level);

  aslmsg asl_msg = asl_new(ASL_TYPE_MSG);
  asl_set(asl_msg, ASL_KEY_MSG, message);
  asl_set(asl_msg, ASL_KEY_LEVEL, level_str);
  asl_send(client, asl_msg);
  asl_free(asl_msg);
}

void RXCFLog(const char* facility, int level, CFStringRef format, ...)
{
  va_list args;
  va_start(args, format);

  CFStringRef userString = CFStringCreateWithFormatAndArguments(kCFAllocatorDefault, nullptr, format, args);
  CFStringRef facilityString = CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, facility, kCFStringEncodingASCII, kCFAllocatorNull);
  CFDateRef now = CFDateCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent());
  char* threadName = RXCopyThreadName();

  CFStringRef message = CFStringCreateWithFormat(kCFAllocatorDefault, nullptr, (CFStringRef)RX_log_format, now, threadName, facilityString, userString);
  char* message_utf8 = const_cast<char*>(CFStringGetCStringPtr(message, kCFStringEncodingUTF8));
  bool free_message = false;
  if (message_utf8 == nullptr) {
    CFIndex message_length = CFStringGetLength(message);
    CFIndex message_max_size = CFStringGetMaximumSizeForEncoding(message_length, kCFStringEncodingUTF8);
    CFIndex message_size = 0;
    message_utf8 = new char[message_max_size + 1];
    CFStringGetBytes(message, CFRangeMake(0, message_length), kCFStringEncodingUTF8, 0, false, reinterpret_cast<UInt8*>(message_utf8), message_max_size, &message_size);
    message_utf8[message_size] = 0;
    free_message = true;
  }

  LogWithASL(message_utf8, level);

  if (free_message) {
    delete[] message_utf8;
  }
  free(threadName);
  CFRelease(message);
  CFRelease(now);
  CFRelease(facilityString);
  CFRelease(userString);

  va_end(args);
}

void RXLog(const char* facility, int level, NSString* format, ...)
{
  va_list args;
  va_start(args, format);
  RXLogv(facility, level, format, args);
  va_end(args);
}

void RXLogv(const char* facility, int level, NSString* format, va_list args)
{
  NSString* userString = [[NSString alloc] initWithFormat:format arguments:args];
  NSString* facilityString = [[NSString alloc] initWithCString:facility encoding:NSASCIIStringEncoding];
  NSDate* now = [NSDate new];
  char* threadName = RXCopyThreadName();

  NSString* message = [[NSString alloc] initWithFormat:RX_log_format, now, threadName, facilityString, userString];
  LogWithASL([message UTF8String], level);

  free(threadName);
  [message release];
  [now release];
  [facilityString release];
  [userString release];
}

void _RXOLog(id object, const char* facility, int level, NSString* format, ...)
{
  va_list args;
  va_start(args, format);

  NSString* userString = [[NSString alloc] initWithFormat:format arguments:args];

  RXLog(facility, level, @"%@: %@", [object description], userString);

  [userString release];
  va_end(args);
}
