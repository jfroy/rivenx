//
//  BZFSOperation.m
//  rivenx
//
//  Created by Jean-Francois Roy on 08/02/2008.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "Utilities/BZFSOperation.h"


@interface BZFSOperation(BZFSOperationPrivate)
- (void)_updateStatus:(NSString*)item stage:(FSFileOperationStage)stage error:(NSError*)error status:(NSDictionary*)status;
@end

static const void* _BZFSOperationRetainObjCObject(const void* info) {
    return [(id)info retain];
}

static void _BZFSOperationReleaseObjCObject(const void* info) {
    [(id)info release];
}

static CFStringRef _BZFSOperationDescribeObjCObject(const void* info) {
    return CFStringCreateCopy(NULL, (CFStringRef)[(id)info description]);
}

static void _BZFSOperationStatusCallback(FSFileOperationRef fileOp, const char* currentItem, FSFileOperationStage stage, OSStatus error, CFDictionaryRef statusDictionary, void* info) {
    [(BZFSOperation*)info _updateStatus:[NSString stringWithUTF8String:currentItem] stage:stage error:[RXError errorWithDomain:NSOSStatusErrorDomain code:error userInfo:nil] status:(NSDictionary*)statusDictionary];
}

@implementation BZFSOperation

+ (BOOL)accessInstanceVariablesDirectly {
    return NO;
}

- (id)initCopyOperationWithSource:(NSString*)source destination:(NSString*)destination {
    self = [super init];
    if (!self)
        return nil;
    
    _type = BZFSOperationCopyOperation;
    
    if (!source || !destination)
        goto BailOut;
    _source = [source copy];
    _destination = [destination copy];
    
    _op = FSFileOperationCreate(NULL);
    if (_op == NULL)
        goto BailOut;
    _options = kFSFileOperationDefaultOptions;
    
    _item = nil;
    _stage = kFSOperationStageUndefined;
    _status = nil;
    _error = nil;
    
    return self;
    
BailOut:
    [self release];
    return nil;
}

- (void)dealloc {
    CFRelease(_op);
    
    [_source release];
    [_destination release];
    
    [_item release];
    [_status release];
    [_error release];
    
    [super dealloc];
}

- (void)_updateStatus:(NSString*)item stage:(FSFileOperationStage)stage error:(NSError*)error status:(NSDictionary*)status {
    id old;
    
    [self willChangeValueForKey:@"item"];
    [self willChangeValueForKey:@"stage"];
    [self willChangeValueForKey:@"status"];
    [self willChangeValueForKey:@"error"];
    
    old = _item;
    _item = [item copy];
    [old release];
    
    _stage = stage;
    
    old = _status;
    _status = [status copy];
    [old release];
    
    old = _error;
    _error = [error copy];
    [old release];
    
    [self didChangeValueForKey:@"error"];
    [self didChangeValueForKey:@"status"];
    [self didChangeValueForKey:@"stage"];
    [self didChangeValueForKey:@"item"];
}

- (BOOL)allowOverwriting {
    return (_options & kFSFileOperationOverwrite) ? YES : NO;
}

- (void)setAllowOverwriting:(BOOL)allow {
    [self willChangeValueForKey:@"allowOverwriting"];
    if (allow)
        _options |= kFSFileOperationOverwrite;
    else
        _options &= ~kFSFileOperationOverwrite;
    [self didChangeValueForKey:@"allowOverwriting"];
}

- (BOOL)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode error:(NSError**)error {
    OSStatus err = FSFileOperationScheduleWithRunLoop(_op, [aRunLoop getCFRunLoop], (CFStringRef)mode);
    if (err != noErr)
        ReturnValueWithError(NO, NSOSStatusErrorDomain, err, nil, error);
    return YES;
}

- (BOOL)start:(NSError**)error {
    FSFileOperationClientContext cc = {0, self, _BZFSOperationRetainObjCObject, _BZFSOperationReleaseObjCObject, _BZFSOperationDescribeObjCObject};
    OSStatus err = paramErr;
    if (_type == BZFSOperationCopyOperation)
        err = FSPathCopyObjectAsync(_op, [_source UTF8String], [_destination UTF8String], NULL, _options, _BZFSOperationStatusCallback, 1.0, &cc);
    if (err != noErr)
        ReturnValueWithError(NO, NSOSStatusErrorDomain, err, nil, error);
    return YES;
}

- (BOOL)cancel:(NSError**)error {
    OSStatus err = FSFileOperationCancel(_op);
    if (err != noErr)
        ReturnValueWithError(NO, NSOSStatusErrorDomain, err, nil, error);
    _cancelled = YES;
    return YES;
}

- (NSString*)item {
    return _item;
}

- (FSFileOperationStage)stage {
    return _stage;
}

- (NSDictionary*)status {
    return _status;
}

- (NSError*)error {
    return _error;
}

@end
