//
//  MHKFileHandle.m
//  MHKKit
//
//  Created by Jean-Francois Roy on 07/04/2005.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "MHKFileHandle.h"
#import "MHKArchive.h"
#import "MHKErrors.h"
#import "Base/RXErrorMacros.h"


@implementation MHKFileHandle

- (id)init
{
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)_initWithArchive:(MHKArchive*)archive fork:(SInt16)forkRef descriptor:(NSDictionary*)desc
{
    self = [super init];
    if (!self)
        return nil;
    
    __owner = [archive retain];
    __forkRef = forkRef;
    
    __offset = [[desc objectForKey:@"Offset"] longLongValue];
    __position = 0;
    __length = [[desc objectForKey:@"Length"] unsignedIntValue];
    
    return self;
}

- (id)_initWithArchive:(MHKArchive*)archive fork:(SInt16)forkRef soundDescriptor:(NSDictionary*)sdesc
{
    self = [super init];
    if (!self)
        return nil;
    
    __owner = [archive retain];
    __forkRef = forkRef;
    
    __offset = [[sdesc objectForKey:@"Samples Absolute Offset"] longLongValue];
    __position = 0;
    __length = [[sdesc objectForKey:@"Samples Length"] unsignedIntValue];
    
    return self;
}

- (void)dealloc
{
    [__owner release];
    [super dealloc];
}

- (MHKArchive*)archive
{
    return __owner;
}

- (NSData*)readDataOfLength:(size_t)length error:(NSError**)error
{
    void* buffer = malloc(length);
    release_assert(buffer);
    
    ssize_t bytes_read = [self readDataOfLength:length inBuffer:buffer error:error];
    if (bytes_read == -1)
    {
        free(buffer);
        return nil;
    }
    
    return [NSData dataWithBytesNoCopy:buffer length:bytes_read freeWhenDone:YES];
}

- (NSData*)readDataToEndOfFile:(NSError**)error
{
    return [self readDataOfLength:__length error:error];
}

- (ssize_t)readDataOfLength:(size_t)length inBuffer:(void*)buffer error:(NSError**)error
{
    // is the request valid?
    if (__position == __length)
        ReturnValueWithError(-1, NSOSStatusErrorDomain, eofErr, nil, error);
    
    if (__length - __position < length)
        length = __length - __position;
    
    // read the data from the file
    ByteCount bytes_read = 0;
    OSStatus err = FSReadFork(__forkRef, fsFromStart | forceReadMask, __offset + __position, length, buffer, &bytes_read);
    if (err && err != eofErr)
        ReturnValueWithError(-1, NSOSStatusErrorDomain, err, nil, error);
    
    // update the position
    __position += bytes_read;
    
    if (err)
        ReturnValueWithError(bytes_read, NSOSStatusErrorDomain, err, nil, error);
    return bytes_read;
}

- (ssize_t)readDataToEndOfFileInBuffer:(void*)buffer error:(NSError**)error
{
    return [self readDataOfLength:__length inBuffer:buffer error:error];
}

- (off_t)offsetInFile
{
    return __position;
}

- (off_t)seekToEndOfFile
{
    __position = __length;
    return __position;
}

- (off_t)seekToFileOffset:(SInt64)offset
{
    if (offset > __length)
        return -1;
    
    // Explicit cast OK here, MHK file sizes are 32 bit
    __position = (UInt32)offset;
    return __position;
}

- (off_t)length
{
    return (SInt64)__length;
}

@end
