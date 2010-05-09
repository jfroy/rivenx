//
//  RXWelcomeWindowController.m
//  rivenx
//
//  Created by Jean-Francois Roy on 13/02/2010.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "Application/RXWelcomeWindowController.h"

#import "Engine/RXArchiveManager.h"
#import "Engine/RXWorld.h"

#import "Utilities/BZFSUtilities.h"


static NSInteger string_numeric_insensitive_sort(id lhs, id rhs, void* context) {
    return [(NSString*)lhs compare:rhs options:NSCaseInsensitiveSearch | NSNumericSearch];
}

@interface RXWelcomeWindowController (RXWelcomeWindowControllerPrivate)
- (void)_initializeInstallationUI;
- (void)_showInstallationUI;
- (void)_dismissInstallationUI;
@end

@implementation RXWelcomeWindowController

- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    
    [super dealloc];
}

- (void)windowWillLoad {
    [self setShouldCascadeWindows:NO];
}

- (void)windowDidLoad {
    // configure the welcome window
    [[self window] center];
    
    // start the removable media scan thread
    [NSThread detachNewThreadSelector:@selector(_scanningThread:) toTarget:self withObject:nil];
    
    // register for removable media mount notifications
    NSNotificationCenter* ws_notification_center = [[NSWorkspace sharedWorkspace] notificationCenter];
    [ws_notification_center addObserver:self selector:@selector(_removableMediaMounted:) name:NSWorkspaceDidMountNotification object:nil];
}

- (void)windowWillClose:(NSNotification*)notification {
    if (![[RXWorld sharedWorld] isInstalled])
        [NSApp terminate:nil];
}

- (IBAction)buyRiven:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.google.com/products/catalog?hl=en&cid=11798540492054256128&sa=title"]];
}

- (void)_installFromFolderPanelDidEnd:(NSOpenPanel*)panel returnCode:(int)returnCode contextInfo:(void*)contextInfo {
    alertOrPanelCurrentlyActive = NO;
    
    if (returnCode == NSCancelButton)
        return;
    
    NSString* path = [[panel URL] path];
    
    BOOL removable, writable, unmountable;
    NSString* description, *fsType;
    if (![[NSWorkspace sharedWorkspace] getFileSystemInfoForPath:path isRemovable:&removable isWritable:&writable isUnmountable:&unmountable description:&description type:&fsType]) {
        [NSApp presentError:[RXError errorWithDomain:RXErrorDomain code:kRXErrFailedToGetFilesystemInformation userInfo:nil]];
        return;
    }
    
    if (removable) {
        NSError* error;
        NSDictionary* attributes = BZFSAttributesOfItemAtPath(path, &error);
        if (!attributes) {
            [NSApp presentError:[RXError errorWithDomain:RXErrorDomain code:kRXErrFailedToGetFilesystemInformation userInfo:nil]];
            return;
        }
        NSUInteger fs_init = [attributes fileSystemNumber];
        
        while (![path isEqualToString:@"/"]) {
            NSString* parent = [path stringByDeletingLastPathComponent];
            attributes = BZFSAttributesOfItemAtPath(parent, &error);
            if (!attributes) {
                [NSApp presentError:[RXError errorWithDomain:RXErrorDomain code:kRXErrFailedToGetFilesystemInformation userInfo:nil]];
                return;
            }
            
            NSUInteger fs = [attributes fileSystemNumber];
            if (fs != fs_init)
                break;
            
            path = parent;
        }
        
        [self _initializeInstallationUI];
        [_installingTitleField setStringValue:NSLocalizedStringFromTable(@"SCANNING_MEDIA", @"Welcome", NULL)];
        [_cancelInstallButton setHidden:YES];
        
        [panel orderOut:self];
        [self _showInstallationUI];
        
        [self performSelector:@selector(_performMountScanWithFeedback:) withObject:path inThread:scanningThread];
    } else {
        [self _initializeInstallationUI];
        [_installingTitleField setStringValue:NSLocalizedStringFromTable(@"SCANNING_MEDIA", @"Welcome", NULL)];
        [_cancelInstallButton setHidden:YES];
        
        [panel orderOut:self];
        [self _showInstallationUI];
        
        [self performSelector:@selector(_performFolderScanWithFeedback:) withObject:path inThread:scanningThread];
    }
}

- (IBAction)installFromFolder:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    
    [panel setCanCreateDirectories:NO];
    [panel setAllowsOtherFileTypes:NO];
    [panel setCanSelectHiddenExtension:NO];
    [panel setTreatsFilePackagesAsDirectories:NO];
    
    [panel setMessage:NSLocalizedStringFromTable(@"FOLDER_INSTALL_PANEL_MESSAGE", @"Welcome", NULL)];
    [panel setPrompt:NSLocalizedString(@"CHOOSE", NULL)];
    [panel setTitle:NSLocalizedString(@"CHOOSE", NULL)];
    
    [panel beginSheetForDirectory:@"/Volumes" file:nil types:nil modalForWindow:[self window] modalDelegate:self didEndSelector:@selector(_installFromFolderPanelDidEnd:returnCode:contextInfo:) contextInfo:nil];
    alertOrPanelCurrentlyActive = YES;
}

- (IBAction)cancelInstallation:(id)sender {
    [NSApp abortModal];
}

#pragma mark installation

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
    if ([keyPath isEqualToString:@"progress"]) {
        double oldp = [[change objectForKey:NSKeyValueChangeOldKey] doubleValue];
        double newp = [[change objectForKey:NSKeyValueChangeNewKey] doubleValue];
        
        // do we need to switch the indeterminate state?
        if (oldp < 0.0 && newp >= 0.0) {
            [_installingProgress setIndeterminate:NO];
            [_installingProgress startAnimation:self];
        } else if (oldp >= 0.0 && newp < 0.0) {
            [_installingProgress setIndeterminate:YES];
            [_installingProgress startAnimation:self];
        }
        
        // update the progress
        if (newp >= 0.0)
            [_installingProgress setDoubleValue:newp];
    }
}

- (void)_initializeInstallationUI {
    [_installingTitleField setStringValue:NSLocalizedStringFromTable(@"INSTALLER_PREPARING", @"Installer", NULL)];
    [_installingStatusField setStringValue:@""];
    [_installingProgress setMinValue:0.0];
    [_installingProgress setMaxValue:1.0];
    [_installingProgress setDoubleValue:0.0];
    [_installingProgress setIndeterminate:YES];
    [_installingProgress setUsesThreadedAnimation:YES];
    [_cancelInstallButton setHidden:NO];
}

- (void)_showInstallationUI {
    [_installingProgress startAnimation:self];
    
    // show the installation panel
    [NSApp beginSheet:_installingSheet modalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:installer];
    installerSession = [NSApp beginModalSessionForWindow:_installingSheet];
}

- (void)_dismissInstallationUI {
    if (!installerSession)
        return;
    
    // dismiss the sheet
    [NSApp endModalSession:installerSession];
    installerSession = NULL;
    
    [NSApp endSheet:_installingSheet returnCode:0];
    [_installingSheet orderOut:self];
    [_installingProgress stopAnimation:self];
}

- (void)_beginNewGame {
    [[NSApp delegate] newDocument:nil];
}

- (void)_runInstallerWithMountPaths:(NSDictionary*)mount_paths {
    // create an installer
    installer = [[RXInstaller alloc] initWithMountPaths:mount_paths mediaProvider:self];
    
    // setup the basic installation UI
    [self _initializeInstallationUI];
    
    // show the installation panel
    [self _showInstallationUI];
    
    // observe the installer
    [installer addObserver:self forKeyPath:@"progress" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:NULL];
    [_installingTitleField bind:@"value" toObject:installer withKeyPath:@"stage" options:nil];
    
    // install away
    NSError* error;
    BOOL did_install = [installer runWithModalSession:installerSession error:&error];
    
    // dismiss the installation panel
    [self _dismissInstallationUI];
    
    // we're done with the installer
    [_installingTitleField unbind:@"value"];
    [installer removeObserver:self forKeyPath:@"progress"];
    [installer release], installer = nil;
    
    // if the installation was successful, set a flag in our defaults informing us
    // that we are installed and kick up the game; otherwise, let the application
    // handle the error
    if (did_install) {
        [[RXWorld sharedWorld] setIsInstalled:YES];
        [self close];
        [self performSelector:@selector(_beginNewGame) withObject:nil afterDelay:0.0];
    } else {
        // delete the shared base directory's content
        NSString* shared_base = [[(RXWorld*)g_world worldSharedBase] path];
        NSArray* content = BZFSContentsOfDirectory(shared_base, NULL);
        NSEnumerator* content_e = [content objectEnumerator];
        NSString* dir;
        while ((dir = [content_e nextObject]))
            BZFSRemoveItemAtURL([NSURL fileURLWithPath:[shared_base stringByAppendingPathComponent:dir]], NULL);
        
        if (!([[error domain] isEqualToString:RXErrorDomain] && [error code] == kRXErrInstallerCancelled))
            [NSApp presentError:error];
    }
}

- (BOOL)waitForDisc:(NSString*)disc_name ejectingDisc:(NSString*)path error:(NSError**)error {
    waitedOnDisc = disc_name;
    
    [[NSWorkspace sharedWorkspace] performSelector:@selector(unmountAndEjectDeviceAtPath:) withObject:path inThread:scanningThread];
    
    while (waitedOnDisc) {
        if ([NSApp runModalSession:installerSession] != NSRunContinuesResponse)
            ReturnValueWithError(NO, RXErrorDomain, kRXErrInstallerCancelled, nil, error);
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    }
    
    return YES;
}

- (void)_stopWaitingForDisc:(NSDictionary*)mount_paths {
    if (!waitedOnDisc)
        return;
    
    [installer updatePathsWithMountPaths:mount_paths];
    waitedOnDisc = nil;
}

- (void)_offerToInstallFromDiscAlertDidEnd:(NSAlert*)alert returnCode:(NSInteger)return_code contextInfo:(void*)context {
    alertOrPanelCurrentlyActive = NO;
    NSDictionary* mount_paths = [(NSDictionary*)context autorelease];
    
    // if the user did not choose to install, we're done
    if (return_code != NSAlertFirstButtonReturn)
        return;
    
    // dismiss the alert's sheet window
    [[alert window] orderOut:nil];
    
    // start an installer
    [self _runInstallerWithMountPaths:mount_paths];
}

- (void)_offerToInstallFromDisc:(NSDictionary*)mount_paths {
    // do nothing if there is already an active installer or we're already installed (e.g. an installer finsihed)
    // or there is some panel or alert already being displayed
    if (installer || [[RXWorld sharedWorld] isInstalled] || alertOrPanelCurrentlyActive)
        return;
    
    // dismiss the installation UI to close the "scanning media" panel
    [self _dismissInstallationUI];
    
    NSString* path = [mount_paths objectForKey:@"path"];
    
    NSString* localized_mount_name = [[NSFileManager defaultManager] displayNameAtPath:path];
    if (!localized_mount_name)
        localized_mount_name = [path lastPathComponent];
    
    NSAlert* alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"INSTALL_FROM_DISC_MESSAGE", @"Welcome", NULL), localized_mount_name]];
    [alert setInformativeText:NSLocalizedStringFromTable(@"INSTALL_FROM_DISC_INFO", @"Welcome", NULL)];
    
    [alert addButtonWithTitle:NSLocalizedString(@"INSTALL", NULL)];
    [alert addButtonWithTitle:NSLocalizedString(@"CANCEL", NULL)];
    
    [alert beginSheetModalForWindow:[self window] modalDelegate:self didEndSelector:@selector(_offerToInstallFromDiscAlertDidEnd:returnCode:contextInfo:) contextInfo:[mount_paths retain]];
    alertOrPanelCurrentlyActive = YES;
}

- (void)_offerToInstallFromFolderAlertDidEnd:(NSAlert*)alert returnCode:(NSInteger)return_code contextInfo:(void*)context {
    alertOrPanelCurrentlyActive = NO;
    NSDictionary* mount_paths = [(NSDictionary*)context autorelease];
    
    // if the user did not choose one of the install actions, we're done
    if (return_code == NSAlertThirdButtonReturn)
        return;
    
    // dismiss the alert's sheet window
    [[alert window] orderOut:nil];
    
    // if the user chose to to a direct install, set the world user base override and go
    if (return_code == NSAlertFirstButtonReturn) {
        [[RXWorld sharedWorld] setIsInstalled:YES];
        [[RXWorld sharedWorld] setWorldBaseOverride:[mount_paths objectForKey:@"path"]];
        [self close];
        [self performSelector:@selector(_beginNewGame) withObject:nil afterDelay:0.0];
    } else {
        // otherwise, the user chose to to a copy install,and so run an installer
        [self _runInstallerWithMountPaths:mount_paths];
    }
}

- (void)_offerToInstallFromFolder:(NSDictionary*)mount_paths {
    // do nothing if there is already an active installer or we're already installed (e.g. an installer finsihed)
    // or there is some panel or alert already being displayed
    if (installer || [[RXWorld sharedWorld] isInstalled] || alertOrPanelCurrentlyActive)
        return;
    
    // dismiss the installation UI to close the "scanning media" panel
    [self _dismissInstallationUI];
    
    NSString* path = [mount_paths objectForKey:@"path"];
    
    NSString* localized_mount_name = [[NSFileManager defaultManager] displayNameAtPath:path];
    if (!localized_mount_name)
        localized_mount_name = [path lastPathComponent];
    
    NSAlert* alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"INSTALL_FROM_FOLDER_MESSAGE", @"Welcome", NULL), localized_mount_name]];
    [alert setInformativeText:NSLocalizedStringFromTable(@"INSTALL_FROM_FOLDER_INFO", @"Welcome", NULL)];
    
    [alert addButtonWithTitle:NSLocalizedStringFromTable(@"DIRECT_INSTALL", @"Welcome", NULL)];
    [alert addButtonWithTitle:NSLocalizedStringFromTable(@"COPY_INSTALL", @"Welcome", NULL)];
    [alert addButtonWithTitle:NSLocalizedString(@"CANCEL", NULL)];
    
    [alert beginSheetModalForWindow:[self window] modalDelegate:self didEndSelector:@selector(_offerToInstallFromFolderAlertDidEnd:returnCode:contextInfo:) contextInfo:[mount_paths retain]];
    alertOrPanelCurrentlyActive = YES;
}

#pragma mark removable media

- (BOOL)_checkPathContent:(NSString*)path removable:(BOOL)removable {    
    // basically look for a Data directory with a bunch of .MHK files, possibly an Assets1 directory and an Extras.MHK file
    NSError* error;
    NSArray* content = BZFSContentsOfDirectory(path, &error);
    if (!content)
        return NO;
    
    NSString* data_path = nil;
    NSString* assets_path = nil;
    NSString* all_path = nil;
    NSString* extras_path = nil;
    
    NSEnumerator* enumerator = [content objectEnumerator];
    NSString* item;
    while ((item = [enumerator nextObject])) {
        NSString* item_path = [path stringByAppendingPathComponent:item];
        if ([item caseInsensitiveCompare:@"Data"] == NSOrderedSame)
            data_path = item_path;
        else if ([item caseInsensitiveCompare:@"Assets1"] == NSOrderedSame)
            assets_path = item_path;
        else if ([item caseInsensitiveCompare:@"All"] == NSOrderedSame)
            all_path = item_path;
        else if ([item caseInsensitiveCompare:@"Extras.MHK"] == NSOrderedSame)
            extras_path = item_path;
    }
    
    // if the Data directory is missing, try the path itself as a workaround for allowing to install from a folder containing all the archives
    if (!data_path)
        data_path = path;
    
    // check for the usual suspects
    NSArray* data_archives = [[BZFSContentsOfDirectory(data_path, &error) filteredArrayUsingPredicate:[RXArchiveManager anyArchiveFilenamePredicate]]
                              sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
    if ([data_archives count] == 0)
        return NO;
    
    // if there is an Assets1 directory, it must contain sound archives
    NSArray* assets_archives = nil;
    if (assets_path) {
        assets_archives = [[BZFSContentsOfDirectory(assets_path, &error) filteredArrayUsingPredicate:[RXArchiveManager soundsArchiveFilenamePredicate]]
                           sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
        if ([assets_archives count] == 0)
            return NO;
    }
    
    // if there is an All directory, it will contain archives for aspit
    NSArray* all_archives = nil;
    if (all_path) {
        all_archives = [[BZFSContentsOfDirectory(all_path, &error) filteredArrayUsingPredicate:[RXArchiveManager anyArchiveFilenamePredicate]]
                        sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
        if ([all_archives count] == 0)
            return NO;
    }
    
    // if we didn't find an Extras archive at the top level, look in the Data directory
    if (!extras_path) {
        content = BZFSContentsOfDirectory(data_path, &error);
        enumerator = [content objectEnumerator];
        while ((item = [enumerator nextObject])) {
            NSString* item_path = [data_path stringByAppendingPathComponent:item];
            if ([item caseInsensitiveCompare:@"Extras.MHK"] == NSOrderedSame)
                extras_path = item_path;
        }
    }
    
    // prepare a dictionary containing the relevant paths we've found
    NSDictionary* mount_paths = [NSDictionary dictionaryWithObjectsAndKeys:
        path, @"path",
        
        data_path, @"data path",
        data_archives, @"data archives",
        
        (assets_path) ? (id)assets_path : (id)[NSNull null], @"assets path",
        (assets_archives) ? (id)assets_archives : (id)[NSNull null], @"assets archives",
        
        (all_path) ? (id)all_path : (id)[NSNull null], @"all path",
        (all_archives) ? (id)all_archives : (id)[NSNull null], @"all archives",
        
        (extras_path) ? (id)extras_path : (id)[NSNull null], @"extras path",
        nil];
    
    // everything checks out; if we're not installing, propose to install from this mount, otherwise inform
    // the installer about the new mount paths
    SEL action;
    if (installer && waitedOnDisc)
        action = @selector(_stopWaitingForDisc:);
    else {
        if (removable)
            action = @selector(_offerToInstallFromDisc:);
        else
            action = @selector(_offerToInstallFromFolder:);
    }
    
    [self performSelectorOnMainThread:action withObject:mount_paths waitUntilDone:NO];
    
    return YES;
}

- (void)_performMountScan:(NSString*)path {
    BOOL usable_mount = [self _checkPathContent:path removable:YES];
    if (!usable_mount && installer && waitedOnDisc)
        [[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtPath:path];
}

- (void)_presentErrorSheet:(NSError*)error {
    // dismiss the installation UI to close the "scanning media" panel
    [self _dismissInstallationUI];
    
    [NSApp presentError:error modalForWindow:[self window] delegate:nil didPresentSelector:nil contextInfo:nil];
}

- (void)_performMountScanWithFeedback:(NSString*)path {
    BOOL usable_mount = [self _checkPathContent:path removable:YES];
    if (!usable_mount)
        [self performSelectorOnMainThread:@selector(_presentErrorSheet:) withObject:[RXError errorWithDomain:RXErrorDomain code:kRXErrUnusableInstallMedia userInfo:nil] waitUntilDone:NO];
}

- (void)_performFolderScanWithFeedback:(NSString*)path {
    BOOL usable_mount = [self _checkPathContent:path removable:NO];
    if (!usable_mount)
        [self performSelectorOnMainThread:@selector(_presentErrorSheet:) withObject:[RXError errorWithDomain:RXErrorDomain code:kRXErrUnusableInstallFolder userInfo:nil] waitUntilDone:NO];
}

- (void)_scanningThread:(id)context {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    
    // keep a reference to ourselves
    scanningThread = [NSThread currentThread];
    
    // scan currently mounted media
    [self performSelectorOnMainThread:@selector(_scanMountedMedia) withObject:nil waitUntilDone:NO];
    
    NSRunLoop* rl = [NSRunLoop currentRunLoop];
    
    // keep the run loop alive with a dummy port
    NSPort* port = [NSPort port];
    [port scheduleInRunLoop:rl forMode:NSDefaultRunLoopMode];
    
    // and run our runloop
    while ([rl runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:10.0]]) {
        [pool release];
        pool = [NSAutoreleasePool new];
    }
    
    scanningThread = nil;
    [pool release];
}

- (void)_removableMediaMounted:(NSNotification*)notification {
    NSString* path = [[notification userInfo] objectForKey:@"NSDevicePath"];
    
    // check if the name is interesting, and if it is check the content of the mount
    NSString* mount_name = [path lastPathComponent];
    
    if (waitedOnDisc) {
        if ([mount_name compare:waitedOnDisc options:NSCaseInsensitiveSearch] == NSOrderedSame)
            [self performSelector:@selector(_performMountScan:) withObject:path inThread:scanningThread];
        else
            [[NSWorkspace sharedWorkspace] performSelector:@selector(unmountAndEjectDeviceAtPath:) withObject:path inThread:scanningThread];
        return;
    }
    
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"SELF matches[c] %@", @"^Riven[0-9]?$"];
    if ([predicate evaluateWithObject:mount_name]) {
        [self performSelector:@selector(_performMountScan:) withObject:path inThread:scanningThread];
        return;
    }
    
    if ([mount_name caseInsensitiveCompare:@"Exile DVD"]) {
        [self performSelector:@selector(_performMountScan:) withObject:path inThread:scanningThread];
        return;
    }
}

- (void)_scanMountedMedia {
    // scan all existing mounts
    NSEnumerator* media_enum = [[[NSWorkspace sharedWorkspace] mountedRemovableMedia] objectEnumerator];
    NSString* mount_path;
    while ((mount_path = [media_enum nextObject])) {
        NSNotification* notification = [NSNotification notificationWithName:NSWorkspaceDidMountNotification object:nil userInfo:[NSDictionary dictionaryWithObject:mount_path forKey:@"NSDevicePath"]];
        [self _removableMediaMounted:notification];
    }
}

@end
