// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "Application/RXGOGSetupInstaller.h"

#import <Foundation/NSBundle.h>
#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSTask.h>

#import "Base/RXErrors.h"
#import "Base/RXErrorMacros.h"

#import "Engine/RXWorld.h"

@interface RXGOGSetupInstaller ()
@property (nonatomic, readwrite, copy) NSString* stage;
@property (nonatomic, readwrite) double progress;
@end

@implementation RXGOGSetupInstaller {
  NSURL* _gogSetupURL;
  NSTask* _unpackTask;
  BOOL _cancelled;
}

- (instancetype)initWithGOGSetupURL:(NSURL*)url {
  self = [super init];
  if (!self) {
    return nil;
  }

  _gogSetupURL = [url retain];

  _progress = -1.0;
  self.stage = NSLocalizedStringFromTable(@"INSTALLER_PREPARING", @"Installer", NULL);

  return self;
}

- (void)dealloc {
  debug_assert(_unpackTask == nil);
  [_gogSetupURL release];
  [super dealloc];
}

- (void)runWithCompletionBlock:(void (^)(BOOL success, NSError* error))block {
  NSString* unpackgogsetup_path = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"unpackgogsetup"];
  release_assert(unpackgogsetup_path);

  _unpackTask = [NSTask new];
  [_unpackTask setLaunchPath:unpackgogsetup_path];
  [_unpackTask setCurrentDirectoryPath:[[[RXWorld sharedWorld] worldCacheBase] path]];
  [_unpackTask setArguments:@[ [_gogSetupURL path] ]];

  NSPipe* status_pipe = [NSPipe new];
  [_unpackTask setStandardOutput:status_pipe];

  int status_fd = [[status_pipe fileHandleForReading] fileDescriptor];
  dispatch_source_t status_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, status_fd, 0, QUEUE_MAIN);
  release_assert(status_source);

  NSMutableString* status_string_remainder = [NSMutableString string];

  dispatch_source_set_event_handler(status_source, ^(void) {
    size_t bytes_available = dispatch_source_get_data(status_source);
    if (bytes_available == 0) {
      return;
    }

    char* status_data = malloc(bytes_available);
    ssize_t bytes_read = read(status_fd, status_data, bytes_available);
    NSString* status_string =
        [[NSString alloc] initWithBytesNoCopy:status_data
                                       length:bytes_read
                                     encoding:NSUTF8StringEncoding
                                 freeWhenDone:YES];

    [status_string_remainder appendString:status_string];
    [status_string release];

    __block NSRange last_enclosing_range = NSMakeRange(0, 0);
    __block double new_progress = self.progress;
    [status_string_remainder
        enumerateSubstringsInRange:NSMakeRange(0, [status_string_remainder length])
                           options:NSStringEnumerationByLines
                        usingBlock:^(NSString* substring, NSRange range, NSRange enclosing_range, BOOL* stop) {
                            if (range.location + range.length == enclosing_range.location + enclosing_range.length) {
                              return;
                            }
                            if ([substring hasPrefix:@"<< "]) {
                              new_progress = [[substring substringFromIndex:3] doubleValue];
                            }
                            last_enclosing_range = enclosing_range;
                        }];
    [status_string_remainder
        deleteCharactersInRange:NSMakeRange(0, last_enclosing_range.location + last_enclosing_range.length)];

    self.progress = new_progress;
  });
  dispatch_resume(status_source);

  _unpackTask.terminationHandler = ^(NSTask* task) {
    dispatch_source_cancel(status_source);
    dispatch_release(status_source);
    [[status_pipe fileHandleForReading] closeFile];
    [status_pipe release];

    self.progress = 1.0;

    BOOL success = [_unpackTask terminationStatus] == 0;
    NSError* error = nil;
    if (_cancelled) {
      error = [RXError errorWithDomain:RXErrorDomain code:kRXErrInstallerCancelled userInfo:nil];
    } else if (!success) {
      error = [RXError errorWithDomain:RXErrorDomain code:kRXErrInstallerGOGSetupUnpackFailed userInfo:nil];
    }

    dispatch_async(QUEUE_MAIN, ^{ block(success, error); });

    [_unpackTask release];
    _unpackTask = nil;
  };

  [_unpackTask launch];
  self.stage = NSLocalizedStringFromTable(@"INSTALLER_DATA_COPY", @"Installer", NULL);
}

- (void)cancel {
  if (!_cancelled) {
    _cancelled = YES;
    [_unpackTask terminate];
  }
}

@end
