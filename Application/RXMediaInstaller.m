// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "Application/RXMediaInstaller.h"

#import <Foundation/NSKeyValueObserving.h>

#import "Base/RXErrors.h"
#import "Base/RXErrorMacros.h"

#import "Engine/RXArchiveManager.h"
#import "Engine/RXCard.h"
#import "Engine/RXScriptCommandAliases.h"
#import "Engine/RXScriptCompiler.h"
#import "Engine/RXScriptDecoding.h"
#import "Engine/RXWorld.h"

#import "Utilities/BZFSUtilities.h"
#import "Utilities/NSArray+RXArrayAdditions.h"
#import "Utilities/RXFSCopyOperation.h"

static NSString* const gStacks[] = {@"aspit", @"bspit", @"gspit", @"jspit", @"ospit", @"pspit", @"rspit", @"tspit"};

@interface RXMediaInstaller ()
@property (nonatomic, readwrite, copy) NSString* stage;
@property (nonatomic, readwrite) double progress;
@end

@implementation RXMediaInstaller {
  __weak id<RXMediaInstallerMediaProviderProtocol> _mediaProvider;
  NSString* _destination;
  void (^_completionBlock)(BOOL success, NSError* error);

  uint64_t _totalBytesToCopy;
  uint64_t _totalBytesCopied;
  NSMutableArray* _archiveToCopyPaths;

  NSMutableArray* _discsToProcess;
  NSString* _currentDisc;

  NSString* _dataPath;
  NSArray* _dataArchives;

  NSString* _assetsPath;
  NSArray* _assetsArchives;

  NSString* _allPath;
  NSArray* _allArchives;

  NSString* _extrasPath;

  BOOL _verified;
  BOOL _patchesInstalled;
  BOOL _cancelled;
}

- (instancetype)initWithMountPaths:(NSDictionary*)mount_paths
                     mediaProvider:(id<RXMediaInstallerMediaProviderProtocol>)mediaProvider {
  self = [super init];
  if (!self) {
    return nil;
  }

  debug_assert(mount_paths);
  debug_assert([mediaProvider conformsToProtocol:@protocol(RXMediaInstallerMediaProviderProtocol)]);

  _mediaProvider = mediaProvider;
  _destination = [[[(RXWorld*)g_world worldCacheBase] path] retain];

  _progress = -1.0;
  self.stage = NSLocalizedStringFromTable(@"INSTALLER_PREPARING", @"Installer", NULL);

  [self _updatePathsWithMountPaths:mount_paths];

  return self;
}

- (void)dealloc {
  debug_assert(_completionBlock == nil);

  [_stage release];
  [_destination release];
  [_archiveToCopyPaths release];
  [_discsToProcess release];
  [_currentDisc release];
  [_dataPath release];
  [_dataArchives release];
  [_assetsPath release];
  [_assetsArchives release];
  [_allPath release];
  [_allArchives release];
  [_extrasPath release];
  [super dealloc];
}

- (void)_updatePathsWithMountPaths:(NSDictionary*)mount_paths {
  [_dataPath release];
  [_dataArchives release];
  [_assetsPath release];
  [_assetsArchives release];
  [_allPath release];
  [_allArchives release];
  [_extrasPath release];
  [_currentDisc release];

  _currentDisc = [[mount_paths objectForKey:@"path"] retain];
  release_assert(_currentDisc);

  _dataPath = [[mount_paths objectForKey:@"data path"] retain];
  release_assert(_dataPath);
  _dataArchives = [[mount_paths objectForKey:@"data archives"] retain];
  release_assert(_dataArchives);

  _assetsPath = [mount_paths objectForKey:@"assets path"];
  if ((id)_assetsPath == (id)[NSNull null]) {
    _assetsPath = nil;
    _assetsArchives = nil;
  } else {
    _assetsArchives = [mount_paths objectForKey:@"assets archives"];
    release_assert((id)_assetsArchives != (id)[NSNull null]);
  }
  [_assetsPath retain];
  [_assetsArchives retain];

  _allPath = [mount_paths objectForKey:@"all path"];
  if ((id)_allPath == (id)[NSNull null]) {
    _allPath = nil;
    _allArchives = nil;
  } else {
    _allArchives = [mount_paths objectForKey:@"all archives"];
    release_assert((id)_allArchives != (id)[NSNull null]);
  }
  [_allPath retain];
  [_allArchives retain];

  _extrasPath = [mount_paths objectForKey:@"extras path"];
  if ((id)_extrasPath == (id)[NSNull null]) {
    _extrasPath = nil;
  }
  [_extrasPath retain];
}

- (BOOL)_determineArchivesToCopyFromCurrentDisc:(NSError**)error {
  // build a mega-array of all the archives we need to copy
  [_archiveToCopyPaths release];
  _archiveToCopyPaths = [NSMutableArray new];

  NSMutableSet* archive_names = [NSMutableSet set];

  for (NSString* archive in _dataArchives) {
    if (![archive_names containsObject:archive]) {
      [_archiveToCopyPaths addObject:[_dataPath stringByAppendingPathComponent:archive]];
      [archive_names addObject:archive];
    }
  }

  for (NSString* archive in _assetsArchives) {
    if (![archive_names containsObject:archive]) {
      [_archiveToCopyPaths addObject:[_assetsPath stringByAppendingPathComponent:archive]];
      [archive_names addObject:archive];
    }
  }

  for (NSString* archive in _allArchives) {
    if (![archive_names containsObject:archive]) {
      [_archiveToCopyPaths addObject:[_allPath stringByAppendingPathComponent:archive]];
      [archive_names addObject:archive];
    }
  }

  if (_extrasPath) {
    if (![archive_names containsObject:[_extrasPath lastPathComponent]]) {
      [_archiveToCopyPaths addObject:_extrasPath];
      [archive_names addObject:[_extrasPath lastPathComponent]];
    }
  }

  if ([_archiveToCopyPaths count] == 0) {
    ReturnValueWithError(NO, RXErrorDomain, kRXErrInstallerMissingArchivesOnMedia, nil, error);
  }

  if (![self _updateCopyBytesStatistics:error]) {
    return NO;
  }

  return YES;
}

- (BOOL)_determinePatchArchivesToCopy:(NSError**)error {
  RXStack* bspit = [[RXStack alloc] initWithKey:@"bspit" error:error];
  if (!bspit) {
    return NO;
  }

  RXCardDescriptor* cdesc = [RXCardDescriptor descriptorWithStack:bspit ID:284];
  if (!cdesc) {
    [bspit release];
    return YES;
  }

  RXCard* bspit_284 = [[RXCard alloc] initWithCardDescriptor:cdesc];
  release_assert(bspit_284);
  [bspit release];

  [bspit_284 load];

  uintptr_t hotspot_id = 9;
  RXHotspot* hotspot = (RXHotspot*)NSMapGet([bspit_284 hotspotsIDMap], (void*)hotspot_id);
  if (!hotspot) {
    [bspit_284 release];
    return YES;
  }

  NSDictionary* md_program = [[[hotspot scripts] objectForKey:RXMouseDownScriptKey] objectAtIndexIfAny:0];
  if (!md_program) {
    [bspit_284 release];
    return YES;
  }

  RXScriptCompiler* comp = [[RXScriptCompiler alloc] initWithCompiledScript:md_program];
  release_assert(comp);
  NSMutableArray* dp = [comp decompiledScript];
  release_assert(dp);

  [comp release];
  [bspit_284 release];

  NSDictionary* opcode = [dp objectAtIndexIfAny:4];
  BOOL need_patch = RX_OPCODE_COMMAND_EQ(opcode, RX_COMMAND_ACTIVATE_SLST) && RX_OPCODE_ARG(opcode, 0) == 3;

  if (need_patch) {
    [_archiveToCopyPaths release];
    _archiveToCopyPaths = [NSMutableArray new];

    NSBundle* bundle = [NSBundle mainBundle];
    [_archiveToCopyPaths addObject:[bundle pathForResource:@"b_Data1" ofType:@"MHK" inDirectory:@"patches"]];
    [_archiveToCopyPaths addObject:[bundle pathForResource:@"j_Data3" ofType:@"MHK" inDirectory:@"patches"]];

    if (![self _updateCopyBytesStatistics:error]) {
      return NO;
    }
  }

  return YES;
}

- (BOOL)_updateCopyBytesStatistics:(NSError**)error {
  _totalBytesCopied = 0;
  _totalBytesToCopy = 0;
  for (NSString* archive_path in _archiveToCopyPaths) {
    NSDictionary* attributes = BZFSAttributesOfItemAtPath(archive_path, error);
    if (!attributes) {
      return NO;
    }
    _totalBytesToCopy += [attributes fileSize];
  }
  return YES;
}

- (BOOL)_mediaHasDataArchiveForStackKey:(NSString*)stack_key {
  NSString* regex = [NSString stringWithFormat:@"^%C_Data[0-9]?\\.MHK$", [stack_key characterAtIndex:0]];
  NSPredicate* predicate = [NSPredicate predicateWithFormat:@"SELF matches[c] %@", regex];

  NSArray* content = [_dataArchives filteredArrayUsingPredicate:predicate];
  if ([content count]) {
    return YES;
  }

  content = [_allArchives filteredArrayUsingPredicate:predicate];
  if ([content count]) {
    return YES;
  }

  return NO;
}

- (BOOL)_mediaHasSoundArchiveForStackKey:(NSString*)stack_key {
  NSString* regex = [NSString stringWithFormat:@"^%C_Sounds[0-9]?\\.MHK$", [stack_key characterAtIndex:0]];
  NSPredicate* predicate = [NSPredicate predicateWithFormat:@"SELF matches[c] %@", regex];

  NSArray* content = [_dataArchives filteredArrayUsingPredicate:predicate];
  if ([content count]) {
    return YES;
  }

  content = [_assetsArchives filteredArrayUsingPredicate:predicate];
  if ([content count]) {
    return YES;
  }

  return NO;
}

- (void)_copyArchiveAndThenContinueInstall:(NSString*)archive_path {
  NSString* destination = [_destination stringByAppendingPathComponent:[archive_path lastPathComponent]];
  RXFSCopyOperation* copy_op = [[RXFSCopyOperation alloc] initWithSource:archive_path destination:destination];

  dispatch_queue_t queue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
  __block CFAbsoluteTime progress_update_time = 0;

  [copy_op setStatusQueue:queue callback:^{
    if (_cancelled && !copy_op.cancelled) {
      [copy_op cancel];
    }

    if (copy_op.state == RXFSOperationStateData) {
      CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
      if (now - progress_update_time >= 1) {
        double new_progress =
        MIN(1.0, (double)(_totalBytesCopied + copy_op.bytesCopied) / _totalBytesToCopy);
        dispatch_async(QUEUE_MAIN, ^{ self.progress = new_progress; });
        progress_update_time = now;
      }
    } else if (copy_op.state == RXFSOperationStateDone) {
      _totalBytesCopied += copy_op.totalBytesCopied;

      NSError* error = copy_op.error;
      BOOL ok = (error == nil) && !_cancelled;
      if (ok) {
        NSDictionary* permissions = @{ NSFilePosixPermissions : @(0664) };
        ok = BZFSSetAttributesOfItemAtPath(destination, permissions, &error);
      }

      dispatch_async(QUEUE_MAIN, ^{ [self _continueInstallIfOK:ok lastStageError:error]; });
    }
  }];

  [copy_op start];
  [copy_op release];
  [queue release];
}

#pragma mark -

- (void)_checkCurrentPathsAndThenContinueInstall {
  NSError* error = nil;
  BOOL ok = [self _determineArchivesToCopyFromCurrentDisc:&error];

  if (ok) {
    self.stage = [NSString
        stringWithFormat:NSLocalizedStringFromTable(@"INSTALLER_DATA_COPY_DISC", @"Installer", NULL), _currentDisc];
    self.progress = 0;
  }

  [self _continueInstallIfOK:ok lastStageError:error];
}

- (void)_verifyArchivesAndThenContinueInstall {
  dispatch_async(QUEUE_DEFAULT, ^{
    // check that we have a data and sound archive for every stack
    NSError* error =
    [RXError errorWithDomain:RXErrorDomain code:kRXErrInstallerMissingArchivesAfterInstall userInfo:nil];
    RXArchiveManager* am = [RXArchiveManager sharedArchiveManager];
    size_t n_stacks = sizeof(gStacks) / sizeof(NSString*);
    for (size_t i = 0; i < n_stacks; ++i) {
      NSArray* archives = [am dataArchivesForStackKey:gStacks[i] error:NULL];
      if ([archives count] == 0) {
        dispatch_async(QUEUE_MAIN, ^{ [self _continueInstallIfOK:NO lastStageError:error]; });
        return;
      }

      archives = [am soundArchivesForStackKey:gStacks[i] error:NULL];
      if ([archives count] == 0) {
        dispatch_async(QUEUE_MAIN, ^{ [self _continueInstallIfOK:NO lastStageError:error]; });
        return;
      }
    }

    _verified = YES;
    dispatch_async(QUEUE_MAIN, ^{ [self _continueInstallIfOK:YES lastStageError:nil]; });
  });
}

- (void)_conditionallyInstallPatchArchivesAndThenContinueInstall {
  // FIXME: verify that this does work if the install source is the patched CD edition (i.e. GOG, Steam)

  dispatch_async(QUEUE_DEFAULT, ^{
    NSError* error = nil;
    BOOL ok = [self _determinePatchArchivesToCopy:&error];
    _patchesInstalled = YES;
    dispatch_async(QUEUE_MAIN, ^{ [self _continueInstallIfOK:ok lastStageError:error]; });
  });
}

- (void)_continueInstallIfOK:(BOOL)ok lastStageError:(NSError*)error {
  debug_assert(_completionBlock);

  // if we're cancelled, call the completion block and bail out
  if (_cancelled) {
    _completionBlock(NO, [RXError errorWithDomain:RXErrorDomain code:kRXErrInstallerCancelled userInfo:nil]);
    [_completionBlock release], _completionBlock = nil;
    return;
  }

  // if the last stage failed, call the completion block and bail out
  if (!ok) {
    debug_assert(error);
    _completionBlock(NO, error);
    [_completionBlock release], _completionBlock = nil;
    return;
  }

  // if we have archives to copy, go on to the next one; when the copy is done, this method will be called back
  if ([_archiveToCopyPaths count]) {
    NSString* next_archive = [_archiveToCopyPaths lastObject];
    [_archiveToCopyPaths removeLastObject];
    [self _copyArchiveAndThenContinueInstall:next_archive];
    return;
  }

  // if we have discs left to copy, ask for the next disc; when we get it, update and check paths and then this method
  // will be called back
  if ([_discsToProcess count]) {
    NSString* next_disc = [_discsToProcess lastObject];
    [_discsToProcess removeLastObject];

    self.progress = -1.0;
    self.stage =
        [NSString stringWithFormat:NSLocalizedStringFromTable(@"INSTALLER_INSERT_DISC", @"Installer", NULL), next_disc];

    [_mediaProvider waitForDisc:next_disc ejectingDisc:_currentDisc continuation:^(NSDictionary* mount_paths) {
      debug_assert(mount_paths);
      [self _updatePathsWithMountPaths:mount_paths];
      [self _checkCurrentPathsAndThenContinueInstall];
    }];
    return;
  }

  self.progress = -1.0;
  self.stage = NSLocalizedStringFromTable(@"INSTALLER_FINALIZER", @"Installer", NULL);

  // verify that we have all the archives we need; when the check is done, this method will be called back
  if (!_verified) {
    [self _verifyArchivesAndThenContinueInstall];
  }

  // conditionally install the built-in patch archives
  if (!_patchesInstalled) {
    [self _conditionallyInstallPatchArchivesAndThenContinueInstall];
  }

  // we have gone through all our stages; call the completion block
  _completionBlock(YES, nil);
  [_completionBlock release], _completionBlock = nil;
}

#pragma mark -

- (void)runWithCompletionBlock:(void (^)(BOOL success, NSError* error))block {
  BOOL cd_install = NO;
  size_t n_stacks = sizeof(gStacks) / sizeof(NSString*);
  for (size_t i = 0; i < n_stacks; ++i) {
    if (![self _mediaHasDataArchiveForStackKey:gStacks[i]]) {
      cd_install = YES;
      break;
    }
  }

  _discsToProcess = [NSMutableArray new];
  if (cd_install) {
    [_discsToProcess addObjectsFromArray:@[ @"Riven5", @"Riven4", @"Riven3", @"Riven2", @"Riven1" ]];
    [_discsToProcess removeObject:[_currentDisc lastPathComponent]];
  } else {
    // we need to have a sound archive for every stack
    // NOTE: it is implied if we are here that we have a data archive for every stack
    for (size_t i = 0; i < n_stacks; ++i) {
      if (![self _mediaHasSoundArchiveForStackKey:gStacks[i]]) {
        block(NO, [RXError errorWithDomain:RXErrorDomain code:kRXErrInstallerMissingArchivesOnMedia userInfo:nil]);
        return;
      }
    }
  }

  // stash the completion block away
  _completionBlock = [block copy];

  // begin the install by checking the current paths (which were set in the initializer)
  [self _checkCurrentPathsAndThenContinueInstall];
}

- (void)cancel {
  _cancelled = YES;
}

@end
