//
//  RXFSCopyOperation.m
//  rivenx
//
//  Copyright 2005-2014 MacStorm. All rights reserved.
//

#import "Utilities/RXFSCopyOperation.h"
#import "Base/RXErrorMacros.h"

#import <copyfile.h>

#import <Foundation/NSFileManager.h>

@interface RXFSCopyOperation ()
- (int)_update:(int)what stage:(int)stage state:(copyfile_state_t)state src:(const char *)src dst:(const char *)dst;
@end

static int copyfile_callback(int what, int stage, copyfile_state_t state, const char* src, const char* dst, void* ctx) {
  return [(RXFSCopyOperation*)ctx _update:what stage:stage state:state src:src dst:dst];
};

@implementation RXFSCopyOperation {
  copyfile_state_t _copyState;

  NSString* _source;
  NSString* _destination;

  dispatch_queue_t _queue;
  dispatch_queue_t _statusQueue;
  dispatch_block_t _statusCallback;
}

- (instancetype)init
{
  [self release];
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (instancetype)initWithSource:(NSString*)source destination:(NSString*)destination
{
  self = [super init];
  if (!self)
    return nil;

  if (!source || !destination) {
    [self release];
    return nil;
  }

  _state = RXFSOperationStateReady;

  _copyState = copyfile_state_alloc();
  copyfile_state_set(_copyState, COPYFILE_STATE_STATUS_CB, &copyfile_callback);

  _source = [source copy];
  _destination = [destination copy];

  _queue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);

  return self;
}

- (void)dealloc
{
  [_source release];
  [_destination release];
  [_item release];
  [_extendedAttribute release];
  [_error release];
  [_queue release];
  [_statusQueue release];
  [_statusCallback release];

  copyfile_state_free(_copyState);

  [super dealloc];
}

- (void)setTargetQueue:(dispatch_queue_t)queue
{
  dispatch_set_target_queue(_queue, queue);
}

- (void)setStatusQueue:(dispatch_queue_t)queue callback:(dispatch_block_t)callback
{
  if (_state != RXFSOperationStateReady)
    return;
  dispatch_async(_queue, ^{
    if (_state != RXFSOperationStateReady)
      return;
    [_statusQueue release];
    _statusQueue = [queue retain];
    [_statusCallback release];
    _statusCallback = [callback copy];
  });
}

- (void)start
{
  if (_state != RXFSOperationStateReady)
    return;
  dispatch_async(_queue, ^{
    if (_state != RXFSOperationStateReady)
      return;

    _state = RXFSOperationStatePreflight;
    [self _notify];

    int flags = COPYFILE_ALL|COPYFILE_RECURSIVE;
    if (copyfile([_source fileSystemRepresentation], [_destination fileSystemRepresentation], _copyState, flags) < 0) {
      if (!_error && !_cancelled) {
        SetErrorToPOSIXError(nil, &_error);
      }
    }

    [self _finish];
  });
}

- (void)cancel
{
  _cancelled = YES;
  dispatch_async(_queue, ^{
    [self _finish];
  });
}

- (int)_update:(int)what stage:(int)stage state:(copyfile_state_t)state src:(const char *)src dst:(const char *)dst
{
  if (_cancelled || what == COPYFILE_RECURSE_ERROR)
    return COPYFILE_QUIT;

  if (stage == COPYFILE_ERR) {
    SetErrorToPOSIXError(nil, &_error);
    return COPYFILE_QUIT;
  }

  BOOL need_notify = YES;

  if (what == COPYFILE_RECURSE_FILE && stage == COPYFILE_START) {
    [self _clearItem];
    _item = [[[NSFileManager defaultManager] stringWithFileSystemRepresentation:src length:strlen(src)] retain];
    need_notify = NO;
  } else if (what == COPYFILE_COPY_DATA) {
    _state = RXFSOperationStateData;
    off_t previous_bytes_copied = _bytesCopied;
    copyfile_state_get(state, COPYFILE_STATE_COPIED, &_bytesCopied);
    _totalBytesCopied += (_bytesCopied - previous_bytes_copied);
  } else if (what == COPYFILE_COPY_XATTR) {
    _state = RXFSOperationStateExtendedAttribute;
    char* attribute = NULL;
    copyfile_state_get(state, COPYFILE_STATE_XATTRNAME, &attribute);
    [_extendedAttribute release];
    _extendedAttribute = [[NSString alloc] initWithUTF8String:attribute];
  } else {
    need_notify = NO;
  }

  if (need_notify) {
    [self _notify];
  }

  return COPYFILE_CONTINUE;
}

- (void)_clearItem
{
  [_item release];
  _item = nil;
  [_extendedAttribute release];
  _extendedAttribute = nil;
  _bytesCopied = 0;
}

- (void)_finish
{
  [self _clearItem];
  _state = RXFSOperationStateDone;

  [self _notify];

  [_statusQueue release];
  _statusQueue = nil;
  [_statusCallback release];
  _statusCallback = nil;
}

- (void)_notify
{
  if (!_statusCallback || !_statusQueue)
    return;
  dispatch_async(_statusQueue, _statusCallback);
}

@end
