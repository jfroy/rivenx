//
//  RXEditionInstaller.m
//  rivenx
//
//  Created by Jean-Francois Roy on 08/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "Application/RXInstaller.h"

#import "Engine/RXWorld.h"
#import "Engine/RXArchiveManager.h"

#import "Utilities/BZFSOperation.h"
#import "Utilities/BZFSUtilities.h"


static NSString* gStacks[] = {
    @"aspit",
    @"bspit",
    @"gspit",
    @"jspit",
    @"ospit",
    @"pspit",
    @"rspit",
    @"tspit"
};

static NSInteger string_numeric_insensitive_sort(id lhs, id rhs, void* context) {
    return [(NSString*)lhs compare:rhs options:NSCaseInsensitiveSearch | NSNumericSearch];
}

@implementation RXInstaller

- (id)initWithMountPaths:(NSDictionary*)mount_paths mediaProvider:(id <RXInstallerMediaProviderProtocol>)mp {
    self = [super init];
    if (!self)
        return nil;
    
    assert(mount_paths);
    assert([mp conformsToProtocol:@protocol(RXInstallerMediaProviderProtocol)]);
    
    mediaProvider = mp;
    [self updatePathsWithMountPaths:mount_paths];
    
    progress = -1.0;
    item = nil;
    stage = [NSLocalizedStringFromTable(@"INSTALLER_PREPARING", @"Editions", NULL) retain];
    remainingTime = -1.0;
    
    return self;
}

- (void)dealloc {
    [item release];
    [stage release];
    
    [dataPath release];
    [dataArchives release];
    [assetsPath release];
    [assetsArchives release];
    [extrasPath release];
    
    [discsToProcess release];
    [currentDisc release];
    [destination release];
    
    [super dealloc];
}

- (BOOL)_mediaHasDataArchiveForStackKey:(NSString*)stack_key {
    NSString* regex = [NSString stringWithFormat:@"^%C_Data[0-9]?\\.MHK$", [stack_key characterAtIndex:0]];
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"SELF matches[c] %@", regex];
    
    NSArray* content = [dataArchives filteredArrayUsingPredicate:predicate];
    if ([content count])
        return YES;
    return NO;
}

- (BOOL)_mediaHasSoundArchiveForStackKey:(NSString*)stack_key {
    NSString* regex = [NSString stringWithFormat:@"^%C_Sounds[0-9]?\\.MHK$", [stack_key characterAtIndex:0]];
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"SELF matches[c] %@", regex];
    
    NSArray* content = [dataArchives filteredArrayUsingPredicate:predicate];
    if ([content count])
        return YES;
    else {
        content = [assetsArchives filteredArrayUsingPredicate:predicate];
        if ([content count])
            return YES;
    }
    
    return NO;
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
    if (![object isKindOfClass:[BZFSOperation class]])
        return;
    
    if (![keyPath isEqualToString:@"status"] || [(BZFSOperation*)object stage] != kFSOperationStageRunning)
        return;
    
    uint64_t bytes_copied = [[[(BZFSOperation*)object status] objectForKey:(NSString*)kFSOperationBytesCompleteKey] unsignedLongLongValue];
    
    [self willChangeValueForKey:@"progress"];
    progress = (double)(totalBytesCopied + bytes_copied) / totalBytesToCopy;
    [self didChangeValueForKey:@"progress"];
}

- (BOOL)_copyFileAtPath:(NSString*)path error:(NSError**)error {
    [self setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"INSTALLER_FILE_COPY", @"Editions", NULL), [path lastPathComponent]] forKey:@"stage"];
    
    BZFSOperation* copy_op = [[BZFSOperation alloc] initCopyOperationWithSource:path destination:destination];
    [copy_op setAllowOverwriting:YES];
    if (![copy_op scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode error:error]) {
        [copy_op release];
        return NO;
    }
    
    [copy_op addObserver:self forKeyPath:@"status" options:0 context:NULL];
    
    if (![copy_op start:error]) {
        [copy_op removeObserver:self forKeyPath:@"status"];
        [copy_op release];
        return NO;
    }
    
    while ([copy_op stage] != kFSOperationStageComplete) {
        if (modalSession && [NSApp runModalSession:modalSession] != NSRunContinuesResponse)
            [copy_op cancel:error];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    }
    
    totalBytesCopied += [[[copy_op status] objectForKey:(NSString*)kFSOperationBytesCompleteKey] unsignedLongLongValue];
    
    [copy_op removeObserver:self forKeyPath:@"status"];
    [copy_op release];
    
    NSDictionary* permissions = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:0664] forKey:NSFilePosixPermissions];
    BZFSSetAttributesOfItemAtPath([destination stringByAppendingPathComponent:[path lastPathComponent]], permissions, error);
    
    if (modalSession && [NSApp runModalSession:modalSession] != NSRunContinuesResponse)
        ReturnValueWithError(NO, RXErrorDomain, kRXErrInstallerCancelled, nil, error);
    
    return YES;
}

- (BOOL)_runSingleDiscInstall:(NSError**)error {    
    // build a mega-array of all the archives we need to copy
    NSMutableArray* archive_paths = [NSMutableArray array];
    
    NSEnumerator* e = [dataArchives objectEnumerator];
    NSString* archive;
    while ((archive = [e nextObject]))
        [archive_paths addObject:[dataPath stringByAppendingPathComponent:archive]];
    
    e = [assetsArchives objectEnumerator];
    while ((archive = [e nextObject]))
        [archive_paths addObject:[assetsPath stringByAppendingPathComponent:archive]];
    
    if (extrasPath)
        [archive_paths addObject:extrasPath];
    
    if ([archive_paths count] == 0)
        ReturnValueWithError(NO, RXErrorDomain, kRXErrInstallerMissingArchivesOnMedia, nil, error);
    
    [archive_paths sortUsingFunction:string_numeric_insensitive_sort context:NULL];
    
    // compute how many bytes we have to copy in total
    e = [archive_paths objectEnumerator];
    NSString* archive_path;
    while ((archive_path = [e nextObject])) {
        NSDictionary* attributes = BZFSAttributesOfItemAtPath(archive_path, error);
        if (!attributes)
            return NO;
        
        totalBytesToCopy += [attributes fileSize];
    }
    
    // and copy the archives
    e = [archive_paths objectEnumerator];
    while ((archive_path = [e nextObject])) {
        if (![self _copyFileAtPath:archive_path error:error])
            return NO;
    }
    
    if ([NSApp runModalSession:modalSession] != NSRunContinuesResponse)
        ReturnValueWithError(NO, RXErrorDomain, kRXErrInstallerCancelled, nil, error);
    
    return YES;
}

- (BOOL)_runMultiDiscInstall:(NSError**)error {
    // a multi-disc install is essentially a series of "single-disc" installs, followed by a check to make
    // sure we have a data and sound archive for every stack
    
    // first, run the install for the current disc
    if (![self _runSingleDiscInstall:error])
        return NO;
    
    // iterate over the discs we have left    
    while ([discsToProcess count]) {
        NSString* disc_name = [discsToProcess objectAtIndex:0];
        [discsToProcess removeObjectAtIndex:0];
        
        [self willChangeValueForKey:@"progress"];
        progress = -1.0;
        [self didChangeValueForKey:@"progress"];
        [self setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"INSTALLER_INSERT_DISC", @"Editions", NULL), disc_name] forKey:@"stage"];
        
        // wait for the disc
        if (![mediaProvider waitForDisc:disc_name ejectingDisc:currentDisc error:error])
            return NO;
        
        // run another single disc install with the new mount paths
        totalBytesCopied = 0.0;
        totalBytesToCopy = 0.0;
        
        if (![self _runSingleDiscInstall:error])
            return NO;
    }
    
    // finally, check that we have a data and sound archive for every stack
    
    
    return NO;
}

- (BOOL)runWithModalSession:(NSModalSession)session error:(NSError**)error {
    // we're one-shot
    if (didRun)
        ReturnValueWithError(NO, RXErrorDomain, kRXErrInstallerAlreadyRan, nil, error);
    didRun = YES;
    
    modalSession = session;
    destination = [[[(RXWorld*)g_world worldSharedBase] path] retain];
    totalBytesCopied = 0.0;
    totalBytesToCopy = 0.0;
    
    if ([NSApp runModalSession:modalSession] != NSRunContinuesResponse)
        ReturnValueWithError(NO, RXErrorDomain, kRXErrInstallerCancelled, nil, error);
    
    [self willChangeValueForKey:@"progress"];
    progress = -1.0;
    [self didChangeValueForKey:@"progress"];
    
    BOOL cd_install = NO;
    size_t n_stacks = sizeof(gStacks) / sizeof(NSString*);
    for (size_t i = 0; i < n_stacks; ++i) {
        if (![self _mediaHasDataArchiveForStackKey:gStacks[i]]) {
            cd_install = YES;
            break;
        }
    }
    
    discsToProcess = [NSMutableArray new];
    if (cd_install) {
        [discsToProcess addObjectsFromArray:[NSArray arrayWithObjects:
            @"Riven1",
            @"Riven2",
            @"Riven3",
            @"Riven4",
            @"Riven5",
            nil]];
        
        [discsToProcess removeObject:[currentDisc lastPathComponent]];
    } else {
        // we need to have a sound archive for every stack
        // NOTE: it is implied if we are here that we have a data archive for every stack
        for (size_t i = 0; i < n_stacks; ++i) {
            if (![self _mediaHasSoundArchiveForStackKey:gStacks[i]])
                ReturnValueWithError(NO, RXErrorDomain, kRXErrInstallerMissingArchivesOnMedia, nil, error);
        }
    }
    
    if (cd_install)
        return [self _runMultiDiscInstall:error];
    else
        return [self _runSingleDiscInstall:error];
}

- (void)updatePathsWithMountPaths:(NSDictionary*)mount_paths {
    [dataPath release];
    [dataArchives release];
    [assetsPath release];
    [assetsArchives release];
    [extrasPath release];
    [currentDisc release];
    
    currentDisc = [[mount_paths objectForKey:@"path"] retain];
    assert(currentDisc);
    
    dataPath = [[mount_paths objectForKey:@"data path"] retain];
    assert(dataPath);
    dataArchives = [[mount_paths objectForKey:@"data archives"] retain];
    assert(dataArchives);
    
    assetsPath = [mount_paths objectForKey:@"assets path"];
    if ((id)assetsPath == (id)[NSNull null]) {
        assetsPath = nil;
        assetsArchives = nil;
    } else {    
        assetsArchives = [mount_paths objectForKey:@"assets archives"];
        assert((id)assetsArchives != (id)[NSNull null]);
    }
    [assetsPath retain];
    [assetsArchives retain];
    
    extrasPath = [mount_paths objectForKey:@"extras path"];
    if ((id)extrasPath == (id)[NSNull null])
        extrasPath = nil;
    [extrasPath retain];
}

@end
