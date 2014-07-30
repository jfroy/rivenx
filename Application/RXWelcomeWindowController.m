// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "Application/RXWelcomeWindowController.h"

#import <AppKit/AppKit.h>

#import "Application/RXGOGSetupInstaller.h"

#import "Base/RXErrors.h"
#import "Base/RXErrorMacros.h"
#import "Base/RXThreadUtilities.h"

#import "Engine/RXArchiveManager.h"
#import "Engine/RXWorld.h"

#import "Utilities/BZFSUtilities.h"

static NSInteger string_numeric_insensitive_sort(id lhs, id rhs, void* context) {
  return [(NSString*)lhs compare:rhs options:(NSStringCompareOptions)(NSCaseInsensitiveSearch | NSNumericSearch)];
}

static BOOL filename_is_gog_installer(NSString* filename) {
  NSString* extension = [filename pathExtension];
  return [filename hasPrefix:@"setup_riven"] && [extension isEqualToString:@"exe"];
}

@interface RXWelcomeWindowController ()
@property (nonatomic, assign) IBOutlet NSImageView* backgroundImageView;
@property (nonatomic, assign) IBOutlet NSStackView* welcomeStackView;
@property (nonatomic, strong) IBOutlet NSTextField* welcomeLabel;
@property (nonatomic, assign) IBOutlet NSTextField* installStatusLabel;
@property (nonatomic, assign) IBOutlet NSStackView* installControlsStackView;
@property (nonatomic, assign) IBOutlet NSProgressIndicator* installProgressIndicator;
@property (nonatomic, assign) IBOutlet NSButton* installButton;
@property (nonatomic, assign) IBOutlet NSButton* buyButton;

- (IBAction)buyRiven:(id)sender;
- (IBAction)installFromFolder:(id)sender;
- (IBAction)cancelInstallation:(id)sender;
@end

@implementation RXWelcomeWindowController {
  NSThread* _scanningThread;
  FSEventStreamRef _downloadsFSEventStream;
  NSString* _downloadsFolderPath;
  BOOL _gogInstallerFoundInDownloadsFolder;

  id<RXInstaller> _installer;
  __weak NSString* _waitedOnDisc;
  void (^_waitedOnDiscContinuation)(NSDictionary* mount_paths);

  NSAlert* _gogBuyAlert;
  BOOL _alertOrPanelCurrentlyActive;
}

- (void)_deleteCacheBaseContent {
  NSFileManager* fm = [NSFileManager new];
  NSURL* url = [[RXWorld sharedWorld] worldCacheBase];
  NSArray* contents = [fm contentsOfDirectoryAtURL:url
                        includingPropertiesForKeys:[NSArray array]
                                           options:(NSDirectoryEnumerationOptions)0
                                             error:NULL];
  for (NSURL* url in contents) {
    BZFSRemoveItemAtURL(url, NULL);
  }
  [fm release];
}

- (void)windowWillLoad {
  [self setShouldCascadeWindows:NO];
}

- (void)windowDidLoad {
  // configure the welcome window
  [self.window center];

  // load the welcome message and set it on the welcome label with the first line in bold
  NSURL* welcome_url = [[NSBundle mainBundle] URLForResource:@"Welcome" withExtension:@"txt"];
  NSString* welcome_string = [NSString stringWithContentsOfURL:welcome_url encoding:NSUTF8StringEncoding error:NULL];
  _welcomeLabel.stringValue = welcome_string;
  NSMutableAttributedString* welcome_astring = [_welcomeLabel.attributedStringValue mutableCopy];
  [welcome_astring.string
      enumerateSubstringsInRange:NSMakeRange(0, welcome_astring.string.length)
                         options:NSStringEnumerationByLines
                      usingBlock:^(NSString* substring, NSRange substringRange, NSRange enclosingRange, BOOL* stop) {
                          NSDictionary* attributes = @{
                            NSFontAttributeName : [NSFont
                                boldSystemFontOfSize:[NSFont systemFontSizeForControlSize:_welcomeLabel.controlSize]]
                          };
                          [welcome_astring addAttributes:attributes range:substringRange];
                          *stop = YES;
                      }];
  _welcomeLabel.attributedStringValue = welcome_astring;
  [welcome_astring release];

  // start the removable media scan thread
  [NSThread detachNewThreadSelector:@selector(_scanningThread:) toTarget:self withObject:nil];

  // register for removable media mount notifications
  NSNotificationCenter* ws_notification_center = [[NSWorkspace sharedWorkspace] notificationCenter];
  [ws_notification_center addObserver:self
                             selector:@selector(_removableMediaMounted:)
                                 name:NSWorkspaceDidMountNotification
                               object:nil];

  // scan for currently mounted media
  [self _scanMountedMedia];

  // scan for the GOG.com installer in the user's Downloads directory
  [self _scanDownloads];

  // nuke everything in the cache base (i.e. old data)
  dispatch_async(QUEUE_LOW, ^(void) { [self _deleteCacheBaseContent]; });
}

- (void)windowWillClose:(NSNotification*)notification {
  if (![[RXWorld sharedWorld] isInstalled]) {
    [NSApp terminate:nil];
  }

  // stop watching removable media
  [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];

  // dismiss sheets and panels
  [self _dismissBuyFromGOGAlert];

  // stop watching the downloads folder
  if (_downloadsFSEventStream) {
    FSEventStreamStop(_downloadsFSEventStream);
    FSEventStreamInvalidate(_downloadsFSEventStream);
    FSEventStreamRelease(_downloadsFSEventStream);
  }

  [_downloadsFolderPath release];
  [_welcomeLabel release];
}

- (IBAction)buyRiven:(id)sender {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL URLWithString:@"http://www.gog.com/game/riven_the_sequel_to_myst"]];

  [_gogBuyAlert release];
  _gogBuyAlert = [NSAlert new];

  [_gogBuyAlert setMessageText:NSLocalizedStringFromTable(@"BUY_FROM_GOG_MESSAGE", @"Welcome", NULL)];
  [_gogBuyAlert setInformativeText:NSLocalizedStringFromTable(@"BUY_FROM_GOG_INFO", @"Welcome", NULL)];

  [_gogBuyAlert addButtonWithTitle:@"OK"];

  [_gogBuyAlert beginSheetModalForWindow:[self window] modalDelegate:self didEndSelector:nil contextInfo:NULL];
}

- (BOOL)panel:(id)sender shouldEnableURL:(NSURL*)url {
  NSString* path = [[url filePathURL] path];
  if (!path) {
    return NO;
  }

  BOOL isDir;
  [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];

  if (isDir) {
    return ![[NSWorkspace sharedWorkspace] isFilePackageAtPath:path];
  } else {
    return filename_is_gog_installer([path lastPathComponent]);
  }
}

- (IBAction)installFromFolder:(id)sender {
  NSOpenPanel* panel = [NSOpenPanel openPanel];
  [panel setCanChooseFiles:YES];
  [panel setCanChooseDirectories:YES];
  [panel setAllowsMultipleSelection:NO];

  [panel setCanCreateDirectories:NO];
  [panel setAllowsOtherFileTypes:NO];
  [panel setCanSelectHiddenExtension:NO];
  [panel setTreatsFilePackagesAsDirectories:NO];

  [panel setMessage:NSLocalizedStringFromTable(@"INSTALL_FROM_PANEL_MESSAGE", @"Welcome", NULL)];
  [panel setPrompt:NSLocalizedString(@"CHOOSE", NULL)];
  [panel setTitle:NSLocalizedString(@"CHOOSE", NULL)];

  [panel setDelegate:self];

  [panel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result) {
    _alertOrPanelCurrentlyActive = NO;

    if (result == NSCancelButton)
      return;

    NSURL* url = [panel URL];

    NSError* error;
    NSArray* resource_keys = @[ NSURLVolumeURLKey, NSURLVolumeIsEjectableKey, NSURLFileResourceTypeKey ];
    NSDictionary* attributes = [url resourceValuesForKeys:resource_keys error:&error];
    if (!attributes) {
      [NSApp presentError:[RXError errorWithDomain:RXErrorDomain
                                              code:kRXErrFailedToGetFilesystemInformation
                                          userInfo:nil]];
      return;
    }

    if ([attributes[NSURLFileResourceTypeKey] isEqualToString:NSURLFileResourceTypeRegular]) {
      [panel orderOut:self];
      [self _offerToInstallFromGOGInstaller:@{@"gog_installer": [panel URL]}];
      return;
    }

    BOOL removable = [attributes[NSURLVolumeIsEjectableKey] boolValue];
    SEL scan_selector = (removable) ? @selector(_performMountScanWithFeedback:)
                                    : @selector(_performFolderScanWithFeedback:);
    if (removable) {
      url = attributes[NSURLVolumeURLKey];
    }

    [_installStatusLabel setStringValue:NSLocalizedStringFromTable(@"SCANNING_MEDIA", @"Welcome", NULL)];

    [self performSelector:scan_selector onThread:_scanningThread withObject:[url path] waitUntilDone:NO];

    [panel orderOut:self];
  }];

  _alertOrPanelCurrentlyActive = YES;
}

- (IBAction)cancelInstallation:(id)sender {
  [_installer cancel];
}

#pragma mark installation

- (void)_beginNewGame {
  [NSApp sendAction:@selector(newDocument:) to:nil from:self];
}

- (void)_beginInstallationWithPaths:(NSDictionary*)paths {
  // transition the UI
  _buyButton.enabled = NO;
  _installButton.enabled = NO;

  _installStatusLabel.stringValue = NSLocalizedStringFromTable(@"INSTALLER_PREPARING", @"Installer", NULL);
  _installStatusLabel.alphaValue = 0;
  _installStatusLabel.hidden = NO;

  _installProgressIndicator.minValue = 0;
  _installProgressIndicator.maxValue = 1;
  _installProgressIndicator.doubleValue = 0;
  _installProgressIndicator.indeterminate = YES;
  _installControlsStackView.alphaValue = 0;
  _installControlsStackView.hidden = NO;

  _welcomeStackView.wantsLayer = YES;

  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
    context.duration = 0.5;
    context.allowsImplicitAnimation = YES;
    _welcomeLabel.alphaValue = 0;
  } completionHandler:^{
    [_welcomeStackView removeView:_welcomeLabel];
    [_welcomeStackView layoutSubtreeIfNeeded];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
      context.duration = 0.5;
      context.allowsImplicitAnimation = YES;
      _installStatusLabel.alphaValue = 1;
      _installControlsStackView.alphaValue = 1;
    } completionHandler:^{
      _welcomeStackView.wantsLayer = NO;
      [self _runInstallerWithPaths:paths];
    }];
  }];
}

- (void)_runInstallerWithPaths:(NSDictionary*)paths {
  // create an installer
  NSURL* gogSetupURL = [paths objectForKey:@"gog_installer"];
  if (gogSetupURL == nil) {
    _installer = [[RXMediaInstaller alloc] initWithMountPaths:paths mediaProvider:self];
  } else {
    _installer = [[RXGOGSetupInstaller alloc] initWithGOGSetupURL:gogSetupURL];
  }
  [(NSObject*)_installer
      addObserver:self
       forKeyPath:@"progress"
          options:(NSKeyValueObservingOptions)(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
          context:NULL];

  [_installStatusLabel bind:@"value" toObject:_installer withKeyPath:@"stage" options:nil];
  [_installProgressIndicator startAnimation:self];

  // install away
  [_installer runWithCompletionBlock:^(BOOL success, NSError* error) {
    [_installStatusLabel unbind:@"value"];
    [_installProgressIndicator stopAnimation:self];

    [(NSObject*)_installer removeObserver:self forKeyPath:@"progress"];
    [_installer release], _installer = nil;

    [_waitedOnDiscContinuation release], _waitedOnDiscContinuation = nil;
    _waitedOnDisc = nil;

    [self _finishInstallaton:success error:error];
  }];
}

- (void)_finishInstallaton:(BOOL)did_install error:(NSError*)error {
  if (did_install) {
    // mark ourselves as installed
    [[RXWorld sharedWorld] setIsInstalled:YES];

    // close the welcome window
    [self close];

    // begin a new game on the next event cycle
    [self performSelector:@selector(_beginNewGame) withObject:nil afterDelay:0.0];

    // all done
    return;
  }

  // nuke everything in the cache base
  dispatch_async(QUEUE_LOW, ^(void) { [self _deleteCacheBaseContent]; });

  // transition the UI
  _welcomeStackView.wantsLayer = YES;

  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
    context.duration = 0.5;
    context.allowsImplicitAnimation = YES;
    _installStatusLabel.alphaValue = 0;
    _installControlsStackView.alphaValue = 0;
  } completionHandler:^{
    _installStatusLabel.stringValue = @"";
    _installStatusLabel.hidden = YES;
    _installControlsStackView.hidden = YES;
    [_welcomeStackView addView:_welcomeLabel inGravity:NSStackViewGravityTop];
    [_welcomeStackView layoutSubtreeIfNeeded];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
      context.duration = 0.5;
      context.allowsImplicitAnimation = YES;
      _welcomeLabel.alphaValue = 1;
    } completionHandler:^{
      _buyButton.enabled = YES;
      _installButton.enabled = YES;
      _welcomeStackView.wantsLayer = NO;
    }];
  }];

  // if the installation failed because of an error (as opposed to cancellation), display the error to the user
  if (!([[error domain] isEqualToString:RXErrorDomain] && [error code] == kRXErrInstallerCancelled)) {
    [NSApp presentError:error];
  }
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context {
  if ([keyPath isEqualToString:@"progress"]) {
    double oldp = [[change objectForKey:NSKeyValueChangeOldKey] doubleValue];
    double newp = [[change objectForKey:NSKeyValueChangeNewKey] doubleValue];

    // do we need to switch the indeterminate state?
    if (oldp < 0.0 && newp >= 0.0) {
      _installProgressIndicator.indeterminate = NO;
    } else if (oldp >= 0.0 && newp < 0.0) {
      [_installProgressIndicator setIndeterminate:YES];
    }

    // update the progress
    if (newp >= 0.0)
      _installProgressIndicator.doubleValue = newp;
  }
}

- (void)waitForDisc:(NSString*)disc_name
       ejectingDisc:(NSString*)path
       continuation:(void (^)(NSDictionary* mount_paths))continuation {
  debug_assert(_waitedOnDisc == nil);
  debug_assert(_waitedOnDiscContinuation == nil);
  _waitedOnDisc = disc_name;
  _waitedOnDiscContinuation = [continuation copy];
  [[NSWorkspace sharedWorkspace] performSelector:@selector(unmountAndEjectDeviceAtPath:)
                                        onThread:_scanningThread
                                      withObject:path
                                   waitUntilDone:NO];
}

- (void)_stopWaitingForDisc:(NSDictionary*)mount_paths {
  debug_assert(_waitedOnDisc != nil);
  debug_assert(_waitedOnDiscContinuation != nil);
  _waitedOnDiscContinuation(mount_paths);
  [_waitedOnDiscContinuation release], _waitedOnDiscContinuation = nil;
  _waitedOnDisc = nil;
}

- (void)_dismissBuyFromGOGAlert {
  // dismiss the GOG.com alert (if present)
  if (_gogBuyAlert) {
    [NSApp endSheet:[_gogBuyAlert window] returnCode:0];
    [[_gogBuyAlert window] orderOut:self];
    [_gogBuyAlert release];
    _gogBuyAlert = nil;
  }
}

- (void)_offerToInstallFromDisc:(NSDictionary*)mount_paths {
  // do nothing if there is already an active installer or we're already installed (e.g. an installer finsihed)
  // or there is some panel or alert already being displayed
  if (_installer || [[RXWorld sharedWorld] isInstalled] || _alertOrPanelCurrentlyActive) {
    return;
  }

  // dismiss sheets and panels
  [self _dismissBuyFromGOGAlert];

  NSString* path = [mount_paths objectForKey:@"path"];

  NSString* localized_mount_name = [[NSFileManager defaultManager] displayNameAtPath:path];
  if (!localized_mount_name) {
    localized_mount_name = [path lastPathComponent];
  }

  NSAlert* alert = [[NSAlert new] autorelease];
  [alert setMessageText:[NSString
                            stringWithFormat:NSLocalizedStringFromTable(@"INSTALL_FROM_DISC_MESSAGE", @"Welcome", NULL),
                                             localized_mount_name]];
  [alert setInformativeText:NSLocalizedStringFromTable(@"INSTALL_FROM_DISC_INFO", @"Welcome", NULL)];

  [alert addButtonWithTitle:NSLocalizedString(@"INSTALL", NULL)];
  [alert addButtonWithTitle:NSLocalizedString(@"CANCEL", NULL)];

  [alert beginSheetModalForWindow:[self window]
                    modalDelegate:self
                   didEndSelector:@selector(_offerToInstallFromDiscOrGogAlertDidEnd:returnCode:contextInfo:)
                      contextInfo:[mount_paths retain]];
  _alertOrPanelCurrentlyActive = YES;
}

- (void)_offerToInstallFromFolder:(NSDictionary*)mount_paths {
  // do nothing if there is already an active installer or we're already installed (e.g. an installer finsihed)
  // or there is some panel or alert already being displayed
  if (_installer || [[RXWorld sharedWorld] isInstalled] || _alertOrPanelCurrentlyActive) {
    return;
  }

  // dismiss sheets and panels
  [self _dismissBuyFromGOGAlert];

  NSString* path = [mount_paths objectForKey:@"path"];

  NSString* localized_mount_name = [[NSFileManager defaultManager] displayNameAtPath:path];
  if (!localized_mount_name) {
    localized_mount_name = [path lastPathComponent];
  }

  NSAlert* alert = [[NSAlert new] autorelease];
  [alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(
                                                       @"INSTALL_FROM_FOLDER_MESSAGE", @"Welcome", NULL),
                                                   localized_mount_name]];
  [alert setInformativeText:NSLocalizedStringFromTable(@"INSTALL_FROM_FOLDER_INFO", @"Welcome", NULL)];

  [alert addButtonWithTitle:NSLocalizedStringFromTable(@"DIRECT_INSTALL", @"Welcome", NULL)];
  [alert addButtonWithTitle:NSLocalizedStringFromTable(@"COPY_INSTALL", @"Welcome", NULL)];
  [alert addButtonWithTitle:NSLocalizedString(@"CANCEL", NULL)];

  [alert beginSheetModalForWindow:[self window]
                    modalDelegate:self
                   didEndSelector:@selector(_offerToInstallFromFolderAlertDidEnd:returnCode:contextInfo:)
                      contextInfo:[mount_paths retain]];
  _alertOrPanelCurrentlyActive = YES;
}

- (void)_offerToInstallFromGOGInstaller:(NSDictionary*)mount_paths {
  // do nothing if there is already an active installer or we're already installed (e.g. an installer finsihed)
  // or there is some panel or alert already being displayed
  if (_installer || [[RXWorld sharedWorld] isInstalled] || _alertOrPanelCurrentlyActive) {
    return;
  }

  // dismiss sheets and panels
  [self _dismissBuyFromGOGAlert];

  NSAlert* alert = [[NSAlert new] autorelease];
  [alert setMessageText:NSLocalizedStringFromTable(@"INSTALL_FROM_GOG_MESSAGE", @"Welcome", NULL)];
  [alert setInformativeText:NSLocalizedStringFromTable(@"INSTALL_FROM_GOG_INFO", @"Welcome", NULL)];

  [alert addButtonWithTitle:NSLocalizedString(@"INSTALL", NULL)];
  [alert addButtonWithTitle:NSLocalizedString(@"CANCEL", NULL)];

  [alert beginSheetModalForWindow:[self window]
                    modalDelegate:self
                   didEndSelector:@selector(_offerToInstallFromDiscOrGogAlertDidEnd:returnCode:contextInfo:)
                      contextInfo:[mount_paths retain]];
  _alertOrPanelCurrentlyActive = YES;
}

- (void)_offerToInstallFromDiscOrGogAlertDidEnd:(NSAlert*)alert
                                     returnCode:(NSInteger)return_code
                                    contextInfo:(void*)context {
  _alertOrPanelCurrentlyActive = NO;
  NSDictionary* mount_paths = [(NSDictionary*)context autorelease];

  // if the user did not choose to install, we're done
  if (return_code != NSAlertFirstButtonReturn) {
    return;
  }

  // dismiss the alert's sheet window
  [[alert window] orderOut:nil];

  // start an installer
  [self _beginInstallationWithPaths:mount_paths];
}

- (void)_offerToInstallFromFolderAlertDidEnd:(NSAlert*)alert
                                  returnCode:(NSInteger)return_code
                                 contextInfo:(void*)context {
  _alertOrPanelCurrentlyActive = NO;
  NSDictionary* mount_paths = [(NSDictionary*)context autorelease];

  // if the user did not choose one of the install actions, we're done
  if (return_code == NSAlertThirdButtonReturn) {
    return;
  }

  // dismiss the alert's sheet window
  [[alert window] orderOut:nil];

  // if the user chose to to a direct install, set the world user base override and go
  if (return_code == NSAlertFirstButtonReturn) {
    [[RXWorld sharedWorld] setIsInstalled:YES];
    [[RXWorld sharedWorld] setWorldBaseOverride:[mount_paths objectForKey:@"path"]];
    [self close];
    [self performSelector:@selector(_beginNewGame) withObject:nil afterDelay:0.0];
  } else {
    // otherwise, the user chose a copy install, and so run an installer
    [self _beginInstallationWithPaths:mount_paths];
  }
}

#pragma mark removable media

- (BOOL)_checkPathContent:(NSString*)path removable:(BOOL)removable {
  release_assert(path);

  // basically look for a Data directory with a bunch of .MHK files, possibly an Assets1 directory and an Extras.MHK
  // file
  NSError* error;
  NSArray* content = BZFSContentsOfDirectory(path, &error);
  if (!content) {
    return NO;
  }

  NSString* data_path = nil;
  NSString* assets_path = nil;
  NSString* all_path = nil;
  NSString* extras_path = nil;
  NSString* myst2_path = nil;

  for (NSString* item in content) {
    NSString* item_path = [path stringByAppendingPathComponent:item];
    if ([item caseInsensitiveCompare:@"Data"] == NSOrderedSame) {
      data_path = item_path;
    } else if ([item caseInsensitiveCompare:@"Assets1"] == NSOrderedSame) {
      assets_path = item_path;
    } else if ([item caseInsensitiveCompare:@"All"] == NSOrderedSame) {
      all_path = item_path;
    } else if ([item caseInsensitiveCompare:@"Myst2"] == NSOrderedSame) {
      myst2_path = item_path;
    } else if ([item caseInsensitiveCompare:@"Extras.MHK"] == NSOrderedSame) {
      extras_path = item_path;
    }
  }

  // if the Data directory is missing, try the path itself as a workaround for allowing to install from a folder
  // containing all the archives
  if (!data_path) {
    data_path = path;
  }

  // check for the usual suspects
  NSArray* data_archives = [[BZFSContentsOfDirectory(data_path, &error)
      filteredArrayUsingPredicate:[RXArchiveManager anyArchiveFilenamePredicate]]
      sortedArrayUsingFunction:string_numeric_insensitive_sort
                       context:NULL];
  if ([data_archives count] == 0) {
    return NO;
  }

  // if there is an Assets1 directory, it must contain sound archives
  NSArray* assets_archives = nil;
  if (assets_path) {
    assets_archives = [[BZFSContentsOfDirectory(assets_path, &error)
        filteredArrayUsingPredicate:[RXArchiveManager soundsArchiveFilenamePredicate]]
        sortedArrayUsingFunction:string_numeric_insensitive_sort
                         context:NULL];
    if ([assets_archives count] == 0) {
      return NO;
    }
  }

  // if there is an All directory, it will contain archives for aspit
  NSArray* all_archives = nil;
  if (all_path) {
    all_archives = [[BZFSContentsOfDirectory(all_path, &error)
        filteredArrayUsingPredicate:[RXArchiveManager anyArchiveFilenamePredicate]]
        sortedArrayUsingFunction:string_numeric_insensitive_sort
                         context:NULL];
    if ([all_archives count] == 0) {
      return NO;
    }
  }

  // if we didn't find an Extras archive at the top level, look in the Data directory
  if (!extras_path) {
    content = BZFSContentsOfDirectory(data_path, &error);
    for (NSString* item in content) {
      NSString* item_path = [data_path stringByAppendingPathComponent:item];
      if ([item caseInsensitiveCompare:@"Extras.MHK"] == NSOrderedSame) {
        extras_path = item_path;
        break;
      }
    }

    // also check in 'Myst2' (Exile edition)
    if (!extras_path && myst2_path) {
      content = BZFSContentsOfDirectory(myst2_path, &error);
      for (NSString* item in content) {
        NSString* item_path = [data_path stringByAppendingPathComponent:item];
        if ([item caseInsensitiveCompare:@"Extras.MHK"] == NSOrderedSame) {
          extras_path = item_path;
          break;
        }
      }
    }
  }

  // prepare a dictionary containing the relevant paths we've found
  NSDictionary* mount_paths = @{
    @"path" : path,
    @"data path" : data_path,
    @"data archives" : data_archives,
    @"assets path" : (assets_path) ? assets_path : [NSNull null],
    @"assets archives" : (assets_archives) ? assets_archives : [NSNull null],
    @"all path" : (all_path) ? all_path : [NSNull null],
    @"all archives" : (all_archives) ? all_archives : [NSNull null],
    @"extras path" : (extras_path) ? extras_path : [NSNull null],
  };

  // everything checks out; if we're not installing, propose to install from this mount, otherwise inform
  // the installer about the new mount paths
  SEL action;
  if (_installer && _waitedOnDisc) {
    action = @selector(_stopWaitingForDisc:);
  } else {
    action = (removable) ? @selector(_offerToInstallFromDisc:) : @selector(_offerToInstallFromFolder:);
  }

  [self performSelectorOnMainThread:action withObject:mount_paths waitUntilDone:NO];

  return YES;
}

- (void)_performMountScan:(NSString*)path {
  BOOL usable_mount = [self _checkPathContent:path removable:YES];
  if (!usable_mount && _installer && _waitedOnDisc) {
    [[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtPath:path];
  }
}

- (void)_presentErrorSheet:(NSError*)error {
  // dismiss sheets and panels
  [self _dismissBuyFromGOGAlert];

  [NSApp presentError:error modalForWindow:[self window] delegate:nil didPresentSelector:nil contextInfo:nil];
}

- (void)_performMountScanWithFeedback:(NSString*)path {
  BOOL usable_mount = [self _checkPathContent:path removable:YES];
  if (!usable_mount) {
    dispatch_async(QUEUE_MAIN, ^{
      [self _presentErrorSheet:[RXError errorWithDomain:RXErrorDomain code:kRXErrUnusableInstallMedia userInfo:nil]];
    });
  }
}

- (void)_performFolderScanWithFeedback:(NSString*)path {
  BOOL usable_mount = [self _checkPathContent:path removable:NO];
  if (!usable_mount) {
    dispatch_async(QUEUE_MAIN, ^{
      [self _presentErrorSheet:[RXError errorWithDomain:RXErrorDomain code:kRXErrUnusableInstallFolder userInfo:nil]];
    });
  }
}

- (void)_scanningThread:(id)context __attribute__((noreturn)) {
  _scanningThread = [NSThread currentThread];
  RXThreadRunLoopRun(SEMAPHORE_NULL, "org.macstorm.rivenx.media-scan");
}

- (void)_removableMediaMounted:(NSNotification*)notification {
  NSString* path = [[notification userInfo] objectForKey:@"NSDevicePath"];

  // check if the name is interesting, and if it is check the content of the mount
  NSString* mount_name = [path lastPathComponent];

  if (_waitedOnDisc) {
    if ([mount_name compare:_waitedOnDisc options:NSCaseInsensitiveSearch] == NSOrderedSame) {
      [self performSelector:@selector(_performMountScan:) onThread:_scanningThread withObject:path waitUntilDone:NO];
    } else {
      [[NSWorkspace sharedWorkspace] performSelector:@selector(unmountAndEjectDeviceAtPath:)
                                            onThread:_scanningThread
                                          withObject:path
                                       waitUntilDone:NO];
    }
    return;
  }

  NSPredicate* predicate = [NSPredicate predicateWithFormat:@"SELF matches[c] %@", @"^Riven[0-9]?$"];
  if ([predicate evaluateWithObject:mount_name]) {
    [self performSelector:@selector(_performMountScan:) onThread:_scanningThread withObject:path waitUntilDone:NO];
    return;
  }

  if ([mount_name caseInsensitiveCompare:@"Exile DVD"]) {
    [self performSelector:@selector(_performMountScan:) onThread:_scanningThread withObject:path waitUntilDone:NO];
    return;
  }
}

- (void)_scanMountedMedia {
  // scan all existing mounts
  for (NSString* mount_path in [[NSWorkspace sharedWorkspace] mountedRemovableMedia]) {
    NSNotification* notification =
        [NSNotification notificationWithName:NSWorkspaceDidMountNotification
                                      object:nil
                                    userInfo:[NSDictionary dictionaryWithObject:mount_path forKey:@"NSDevicePath"]];
    [self _removableMediaMounted:notification];
  }
}

#pragma mark GOG.com installer

typedef void (^FSEventsBlock)(ConstFSEventStreamRef streamRef,
                              size_t numEvents,
                              void* eventPaths,
                              const FSEventStreamEventFlags eventFlags[],
                              const FSEventStreamEventId eventIds[]);

static void SetupFSEventStreamCallbackWithBlock(FSEventStreamContext* context, FSEventsBlock block) {
  memset(context, 0, sizeof(FSEventStreamContext));
  context->info = [block copy];
  context->retain = (CFAllocatorRetainCallBack)_Block_copy;
  context->release = (CFAllocatorReleaseCallBack)_Block_release;
}

static void FSEventsBlockCallback(ConstFSEventStreamRef streamRef,
                                  void* clientCallBackInfo,
                                  size_t numEvents,
                                  void* eventPaths,
                                  const FSEventStreamEventFlags eventFlags[],
                                  const FSEventStreamEventId eventIds[]) {
  FSEventsBlock b = (FSEventsBlock)clientCallBackInfo;
  b(streamRef, numEvents, eventPaths, eventFlags, eventIds);
}

- (void)_scanDownloadFolderForGOGInstaller {
  NSFileManager* fm = [NSFileManager new];
  NSURL* url = [NSURL fileURLWithPath:_downloadsFolderPath isDirectory:YES];
  NSArray* contents = [fm contentsOfDirectoryAtURL:url
                        includingPropertiesForKeys:[NSArray array]
                                           options:(NSDirectoryEnumerationOptions)0
                                             error:NULL];
  BOOL found = NO;

  for (NSURL* url in contents) {
    if (filename_is_gog_installer([url lastPathComponent])) {
      if (_gogInstallerFoundInDownloadsFolder == NO) {
        [self _offerToInstallFromGOGInstaller:@{@"gog_installer": url}];
      }
      found = YES;
      break;
    }
  }

  _gogInstallerFoundInDownloadsFolder = found;
  [fm release];
}

- (void)_scanDownloads {
  NSArray* dirs = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES);
  if (![dirs count]) {
    return;
  }

  _downloadsFolderPath = [dirs objectAtIndex:0];
  NSString* resolved =
      [[[NSFileManager new] autorelease] destinationOfSymbolicLinkAtPath:_downloadsFolderPath error:NULL];
  if (resolved) {
    _downloadsFolderPath = resolved;
  }
  [_downloadsFolderPath retain];

  FSEventStreamContext context;
  SetupFSEventStreamCallbackWithBlock(
      &context,
      ^(ConstFSEventStreamRef streamRef,
        size_t numEvents,
        void* eventPaths,
        const FSEventStreamEventFlags eventFlags[],
        const FSEventStreamEventId eventIds[]) {
          [self _scanDownloadFolderForGOGInstaller];
      });

  _downloadsFSEventStream = FSEventStreamCreate(kCFAllocatorDefault,
                                                FSEventsBlockCallback,
                                                &context,
                                                (CFArrayRef)[NSArray arrayWithObject : _downloadsFolderPath],
                                                kFSEventStreamEventIdSinceNow,
                                                2.0,
                                                kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagIgnoreSelf);
  FSEventStreamScheduleWithRunLoop(_downloadsFSEventStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
  FSEventStreamStart(_downloadsFSEventStream);

  // do a scan on the next run loop cycle
  [self performSelector:@selector(_scanDownloadFolderForGOGInstaller) withObject:nil afterDelay:1.0];
}

@end
