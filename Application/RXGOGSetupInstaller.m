//
//  RXGOGSetupInstaller.m
//  rivenx
//
//  Created by Jean-François Roy on 30/12/2011.
//  Copyright (c) 2012 MacStorm. All rights reserved.
//

#import "RXGOGSetupInstaller.h"

#import "RXErrorMacros.h"

#import "RXWorld.h"

#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSTask.h>


@implementation RXGOGSetupInstaller

- (id)initWithGOGSetupURL:(NSURL*)url
{
    self = [super init];
    if (!self)
        return nil;
    
    _gogSetupURL = [url retain];
    
    return self;
}

- (void)dealloc
{
    [_gogSetupURL release];
    
    [super dealloc];
}

- (BOOL)runWithModalSession:(NSModalSession)session error:(NSError**)error
{
    // we're one-shot
    if (didRun)
        ReturnValueWithError(NO, RXErrorDomain, kRXErrInstallerAlreadyRan, nil, error);
    didRun = YES;
    
    modalSession = session;
    destination = [[[(RXWorld*)g_world worldCacheBase] path] retain];
    
    if ([NSApp runModalSession:modalSession] != NSRunContinuesResponse)
        ReturnValueWithError(NO, RXErrorDomain, kRXErrInstallerCancelled, nil, error);
    
    [self willChangeValueForKey:@"progress"];
    progress = -1.0;
    [self didChangeValueForKey:@"progress"];
    
    NSString* unpackgogsetupPath = [[NSBundle mainBundle] pathForResource:@"unpackgogsetup" ofType:@""];
    release_assert(unpackgogsetupPath);
    
    NSTask* unpackgogsetupTask = [NSTask new];
    release_assert(unpackgogsetupTask);
    [unpackgogsetupTask setLaunchPath:unpackgogsetupPath];
    [unpackgogsetupTask setCurrentDirectoryPath:destination];
    [unpackgogsetupTask setArguments:[NSArray arrayWithObject:[_gogSetupURL path]]];
    
    NSPipe* pipe = [NSPipe new];
    [unpackgogsetupTask setStandardOutput:pipe];
    
    int inputFD = [[pipe fileHandleForReading] fileDescriptor];
    dispatch_source_t inputSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, inputFD, 0, QUEUE_MAIN);
    release_assert(inputSource);
    
    dispatch_source_set_event_handler(inputSource, ^(void)
    {
        size_t bytesAvailable = dispatch_source_get_data(inputSource);
        if (bytesAvailable == 0)
            return;
        
        char* input = malloc(bytesAvailable + 1);
        ssize_t bytesRead = read(inputFD, input, bytesAvailable);
        input[bytesRead] = 0;
        
        char* eol = strrchr(input, '\n');
        NSString* lines = [[NSString alloc] initWithBytesNoCopy:input length:eol - input encoding:NSUTF8StringEncoding freeWhenDone:YES];
        [lines enumerateLinesUsingBlock:^(NSString* line, BOOL* stop)
        {
            if (_filesToUnpack == 0)
            {
                _filesToUnpack = [line intValue];
                return;
            }
            
            if ([line hasPrefix:@"<< "])
            {
                double progressFile = [[line substringFromIndex:3] doubleValue];
                
                [self willChangeValueForKey:@"progress"];
                progress = ((_filesUnpacked - 1) + progressFile) / _filesToUnpack;
                [self didChangeValueForKey:@"progress"];
                
                return;
            }
            
            [self setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"INSTALLER_FILE_COPY", @"Installer", NULL), line] forKey:@"stage"];
            
            _filesUnpacked++;
            [self willChangeValueForKey:@"progress"];
            progress = (double)(_filesUnpacked - 1) / _filesToUnpack;
            [self didChangeValueForKey:@"progress"];
        }];
    });
    dispatch_resume(inputSource);
    
    [unpackgogsetupTask launch];
    
    while ([unpackgogsetupTask isRunning])
    {
        if (modalSession && [NSApp runModalSession:modalSession] != NSRunContinuesResponse)
            [unpackgogsetupTask terminate];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    }
    
    dispatch_source_cancel(inputSource);
    dispatch_release(inputSource);
    [[pipe fileHandleForReading] closeFile];
    [pipe release];
    
    BOOL success = [unpackgogsetupTask terminationStatus] == 0;
    [unpackgogsetupTask release];
    
    if ([NSApp runModalSession:modalSession] != NSRunContinuesResponse)
        ReturnValueWithError(NO, RXErrorDomain, kRXErrInstallerCancelled, nil, error);
    
    if (!success)
        ReturnValueWithError(NO, RXErrorDomain, kRXErrInstallerGOGSetupUnpackFailed, nil, error);
    
    [self willChangeValueForKey:@"progress"];
    progress = 1.0;
    [self didChangeValueForKey:@"progress"];
    
    return YES;
}

- (void)updatePathsWithMountPaths:(NSDictionary*)mount_paths
{
    // nothing to do
}

@end
