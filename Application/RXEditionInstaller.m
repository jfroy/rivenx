//
//  RXEditionInstaller.m
//  rivenx
//
//  Created by Jean-Francois Roy on 08/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "Application/RXEditionInstaller.h"

#import "Engine/RXEditionManager.h"
#import "Engine/RXWorld.h"

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

@implementation RXEditionInstaller

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

- (BOOL)_hasDataArchiveForStackKey:(NSString*)stack_key {
    NSString* regex = [NSString stringWithFormat:@"^%C_Data[0-9]?\\.MHK$", [stack_key characterAtIndex:0]];
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"SELF matches[c] %@", regex];
    
    NSArray* content = [dataArchives filteredArrayUsingPredicate:predicate];
    if ([content count])
        return YES;
    return NO;
}

- (BOOL)_hasSoundArchiveForStackKey:(NSString*)stack_key {
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
        if (![self _hasDataArchiveForStackKey:gStacks[i]]) {
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
            if (![self _hasSoundArchiveForStackKey:gStacks[i]])
                ReturnValueWithError(NO, RXErrorDomain, kRXErrInstallerMissingArchives, nil, error);
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

//- (NSString*)_waitForDisc:(NSString*)disc inModalSession:(NSModalSession)session error:(NSError**)error {
//    NSString* mountPath = [[RXEditionManager sharedEditionManager] mountPathForDisc:disc waitingInModalSession:nil];
//    while (!mountPath) {
//        // set the UI to indeterminate waiting for disc
//        [self _updateInstallerProgress:NO];
//        [self setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"INSTALLER_INSERT_DISC", @"Editions", NULL), disc] forKey:@"stage"];
//        
//        mountPath = [[RXEditionManager sharedEditionManager] mountPathForDisc:disc waitingInModalSession:session];
//        if (session && [NSApp runModalSession:session] != NSRunContinuesResponse)
//            ReturnValueWithError(nil, RXErrorDomain, 0, nil, error);
//        if (!mountPath)
//            continue;
//    }
//    
//    return mountPath;
//}

//- (BOOL)_performStackCopy:(NSDictionary*)directive destination:(NSString*)destination modalSession:(NSModalSession)session error:(NSError**)error {
//    NSDictionary* stackDescriptors = [edition valueForKey:@"stackDescriptors"];
//    NSArray* discs = [edition valueForKey:@"discs"];
//    NSDictionary* directories = [edition valueForKey:@"directories"];
//    
//    // step 1: determine which stacks to operate on
//    NSArray* stacks = ([directive objectForKey:@"Include"]) ? [NSArray arrayWithObject:[directive objectForKey:@"Include"]] : [stackDescriptors allKeys];
//    if ([directive objectForKey:@"Exclude"])
//        [(NSMutableArray*)(stacks = [[stacks mutableCopy] autorelease]) removeObject:[directive objectForKey:@"Exclude"]];
//    
//    // step 2: establish a parallel array to the edition's discs mapping disc to stacks (in order to not have the user do mad swapping)
//    NSMutableArray* stacksForDiscs = [NSMutableArray array];
//    uint32_t discIndex = 0;
//    for (; discIndex < [discs count]; discIndex++) {
//        NSMutableArray* discStacks = [NSMutableArray array];
//        [stacksForDiscs addObject:discStacks];
//
//        NSEnumerator* stackKeyEnum = [stacks objectEnumerator];
//        NSString* stackKey;
//        while ((stackKey = [stackKeyEnum nextObject])) {
//            // get the stack descriptor
//            NSDictionary* stackDescriptor = [stackDescriptors objectForKey:stackKey];
//            
//            // get the stack disc (may not be specified, default to 0)
//            uint32_t stackDiscIndex = ([stackDescriptor objectForKey:@"Disc"]) ? [[stackDescriptor objectForKey:@"Disc"] unsignedIntValue] : 0;
//            
//            // if the directive has a disc override, apply it
//            if ([directive objectForKey:@"Disc"])
//                stackDiscIndex = [[directive objectForKey:@"Disc"] unsignedIntValue];
//            
//            // if the disc index matched the current disc index, add the stack key to the array of stacks for the current disc
//            if (stackDiscIndex == discIndex)
//                [discStacks addObject:stackKey];
//        }
//    }
//    
//    // step 3: count the number of discs to process (omitting discs with no stacks to process)
//    _discsProcessed = 0;
//    NSEnumerator* discStacksEnum = [stacksForDiscs objectEnumerator];
//    NSArray* discStacks;
//    while ((discStacks = [discStacksEnum nextObject]))
//        if ([discStacks count] > 0)
//            _discsToProcess++;
//    
//    // step 4: process the stacks of each disc
//    
//    // process the discs
//    discIndex = 0;
//    discStacksEnum = [stacksForDiscs objectEnumerator];
//    while ((discStacks = [discStacksEnum nextObject])) {
//        // ignore the disc if it has no stacks to process
//        if ([discStacks count] == 0) {
//            discIndex++;
//            continue;
//        }
//        
//        // allocate the list of files to copy from that disc
//        NSMutableArray* files_to_copy = [NSMutableArray array];
//        
//        // reset the byte counters
//        _totalBytesToCopy = 0;
//        _totalBytesCopied = 0;
//        
//        // step 4.1: wait for the right disc
//        NSString* disc = [discs objectAtIndex:discIndex];
//        NSString* mount_path = nil;
////        NSString* extras_path = nil;
//        
//        // we will have 0 bytes to copy until we find the right disc
//        while (_totalBytesToCopy == 0) {
//            mount_path = [self _waitForDisc:disc inModalSession:session error:error];
//            if (!mount_path)
//                return NO;
//            
//            // check that every file we need is on that disc, and count the number of bytes to copy at the same time
//            [self _updateInstallerProgress:NO];
//            [self setValue:NSLocalizedStringFromTable(@"INSTALLER_CHECKING_DISC", @"Editions", NULL) forKey:@"stage"];
//            if (session && [NSApp runModalSession:session] != NSRunContinuesResponse)
//                ReturnValueWithError(NO, RXErrorDomain, 0, nil, error);
//            
//            // look for the edition directories on the mount path
//            NSString* all_directory = BZFSSearchDirectoryForItem(mount_path, [directories objectForKey:@"All"], YES, NULL);
//            NSString* data_directory = BZFSSearchDirectoryForItem(mount_path, [directories objectForKey:@"Data"], YES, NULL);
//            NSString* sound_directory = BZFSSearchDirectoryForItem(mount_path, [directories objectForKey:@"Sound"], YES, NULL);
//            
//            // build list of files to copy from the disc
//            NSEnumerator* stack_key_enum = [discStacks objectEnumerator];
//            NSString* stack_key;
//            while ((stack_key = [stack_key_enum nextObject])) {
//                BOOL do_copy;
//                
//                // get the stack descriptor
//                NSDictionary* stack_descriptor = [stackDescriptors objectForKey:stack_key];
//                
//                // data archives
//                do_copy = ([directive objectForKey:@"Copy Data"]) ? [[directive objectForKey:@"Copy Data"] boolValue] : YES;
//                if (do_copy) {
//                    NSString* directory = ([stack_key isEqualToString:@"aspit"]) ? all_directory : data_directory;
//                    
//                    id archives = [stack_descriptor objectForKey:@"Data Archives"];
//                    if ([archives isKindOfClass:[NSString class]])
//                        archives = [NSArray arrayWithObject:archives];
//                    
//                    NSEnumerator* file_enum = [archives objectEnumerator];
//                    NSString* file;
//                    while ((file = [file_enum nextObject])) {
//                        NSString* archive_path = BZFSSearchDirectoryForItem(directory, file, YES, NULL);
//                        if (!archive_path) {
//                            // this is not the right disc, even though it has the right name
//                            [NSThread detachNewThreadSelector:@selector(ejectMountPath:) toTarget:[RXEditionManager sharedEditionManager] withObject:mount_path];
//                            mount_path = nil;
//                            _totalBytesToCopy = 0;
//                            break;
//                        }
//                        
//                        // add the actual path of the archive to the list of files to copy
//                        [files_to_copy addObject:archive_path];
//                        
//                        // get the archive's size and add it to the total byte count
//                        NSDictionary* attributes = BZFSAttributesOfItemAtPath(archive_path, NULL);
//                        if (attributes)
//                            _totalBytesToCopy += [attributes fileSize];
//                    }
//                    
//                    if (!mount_path)
//                        break;
//                }
//                
//                // sound archives
//                do_copy = ([directive objectForKey:@"Copy Sound"]) ? [[directive objectForKey:@"Copy Sound"] boolValue] : YES;
//                if (do_copy) {
//                    NSString* directory = sound_directory;
//                    
//                    id archives = [stack_descriptor objectForKey:@"Sound Archives"];
//                    if ([archives isKindOfClass:[NSString class]])
//                        archives = [NSArray arrayWithObject:archives];
//                    
//                    NSEnumerator* file_enum = [archives objectEnumerator];
//                    NSString* file;
//                    while ((file = [file_enum nextObject])) {
//                        NSString* archive_path = BZFSSearchDirectoryForItem(directory, file, YES, NULL);
//                        if (!archive_path) {
//                            // this is not the right disc, even though it has the right name
//                            [NSThread detachNewThreadSelector:@selector(ejectMountPath:) toTarget:[RXEditionManager sharedEditionManager] withObject:mount_path];
//                            mount_path = nil;
//                            _totalBytesToCopy = 0;
//                            break;
//                        }
//                        
//                        // add the actual path of the archive to the list of files to copy
//                        [files_to_copy addObject:archive_path];
//                        
//                        // get the archive's size and add it to the total byte count
//                        NSDictionary* attributes = BZFSAttributesOfItemAtPath(archive_path, NULL);
//                        if (attributes)
//                            _totalBytesToCopy += [attributes fileSize];
//                    }
//                    
//                    if (!mount_path)
//                        break;
//                }
//            }
//            
//            // try to find Extras.MHK
//            extras_path = [edition searchForExtrasArchiveInMountPath:mount_path];
//            if (extras_path) {
//                [files_to_copy addObject:extras_path];
//                NSDictionary* attributes = BZFSAttributesOfItemAtPath(extras_path, NULL);
//                if (attributes)
//                    _totalBytesToCopy += [attributes fileSize];
//            }
//        }
//        
//        // step 4.2: copy each file
//        
//        // update the progress
//        _directiveProgress = (double)_discsProcessed / _discsToProcess;
//        [self _updateInstallerProgress:YES];
//        
//        NSEnumerator* file_enum = [files_to_copy objectEnumerator];
//        NSString* file_path;
//        while ((file_path = [file_enum nextObject])) {
//            [self setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"INSTALLER_FILE_COPY", @"Editions", NULL), [file_path lastPathComponent]] forKey:@"stage"];
//            
//            BZFSOperation* copyOp = [[BZFSOperation alloc] initCopyOperationWithSource:file_path destination:destination];
//            [copyOp setAllowOverwriting:YES];
//            if (![copyOp scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode error:error]) {
//                [copyOp release];
//                return NO;
//            }
//            
//            [copyOp addObserver:self forKeyPath:@"status" options:0 context:NULL];
//            
//            if (![copyOp start:error]) {
//                [copyOp removeObserver:self forKeyPath:@"status"];
//                [copyOp release];
//                
//                return NO;
//            }
//            
//            while ([copyOp stage] != kFSOperationStageComplete) {
//                if (session && [NSApp runModalSession:session] != NSRunContinuesResponse)
//                    [copyOp cancel:error];
//                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
//            }
//            
//            // update the progress
//            _totalBytesCopied += [[[copyOp status] objectForKey:(NSString*)kFSOperationBytesCompleteKey] unsignedLongLongValue];
//            
//            [copyOp removeObserver:self forKeyPath:@"status"];
//            [copyOp release];
//            
//            if (session && [NSApp runModalSession:session] != NSRunContinuesResponse)
//                return NO;
//        }
//        
//        discIndex++;
//        _discsToProcess++;
//    }
//    
//    return YES;
//}

@end
