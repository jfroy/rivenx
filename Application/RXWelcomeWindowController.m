//
//  RXWelcomeWindowController.m
//  rivenx
//
//  Created by Jean-Francois Roy on 13/02/2010.
//  Copyright 2010 MacStorm. All rights reserved.
//

#import "Application/RXWelcomeWindowController.h"

#import "Engine/RXEditionManager.h"
#import "Utilities/BZFSUtilities.h"


static NSInteger string_numeric_insensitive_sort(id lhs, id rhs, void* context) {
    return [(NSString*)lhs compare:rhs options:NSCaseInsensitiveSearch | NSNumericSearch];
}

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
    [NSApp terminate:nil];
}

- (IBAction)buyRiven:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.google.com/products/catalog?hl=en&cid=11798540492054256128&sa=title"]];
}

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

- (void)_initializeInstallationUI:(RXEditionInstaller*)installer {
    [_installingTitleField setStringValue:NSLocalizedStringFromTable(@"INSTALLER_PREPARING", @"Editions", NULL)];
    [_installingStatusField setStringValue:@""];
    [_installingProgress setMinValue:0.0];
    [_installingProgress setMaxValue:1.0];
    [_installingProgress setDoubleValue:0.0];
    [_installingProgress setIndeterminate:YES];
//    [_installingProgress setUsesThreadedAnimation:YES];
    [_installingProgress startAnimation:self];
}

- (void)_runInstallerWithMountPaths:(NSDictionary*)mount_paths {
    // create an installer
    installer = [[RXEditionInstaller alloc] initWithMountPaths:mount_paths mediaProvider:self];
    
    // setup the basic installation UI
    [self _initializeInstallationUI:installer];
    
    // show the installation panel
    [NSApp beginSheet:_installingSheet modalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:installer];
    installerSession = [NSApp beginModalSessionForWindow:_installingSheet];
    
    // observe the installer
    [installer addObserver:self forKeyPath:@"progress" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:NULL];
    [_installingTitleField bind:@"value" toObject:installer withKeyPath:@"stage" options:nil];
    
    // install away
    NSError* error;
    BOOL did_install = [installer runWithModalSession:installerSession error:&error];
    
    // dismiss the sheet
    [NSApp endModalSession:installerSession];
    installerSession = NULL;
    
    [NSApp endSheet:_installingSheet returnCode:0];
    [_installingSheet orderOut:self];
    [_installingProgress stopAnimation:self];
    
    // we're done with the installer
    [_installingTitleField unbind:@"value"];
    [installer removeObserver:self forKeyPath:@"progress"];
    [installer release];
    
    // if the edition was installed, make it current
//    if (didInstall)
//        [self _makeEditionCurrent:ed];
    if (!did_install)
        NSBeep();
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
    [installer updatePathsWithMountPaths:mount_paths];
    waitedOnDisc = nil;
}

- (void)_didEndOfferToInstallAlert:(NSAlert*)alert returnCode:(NSInteger)return_code contextInfo:(void*)context {
    NSDictionary* mount_paths = [(NSDictionary*)context autorelease];
    
    // if the user did not choose to install, we're done
    if (return_code != NSAlertFirstButtonReturn)
        return;
    
    // dismiss the alert's sheet window
    [[alert window] orderOut:nil];
    
    // start an installer
    [self _runInstallerWithMountPaths:mount_paths];
}

- (void)_offerToInstallFromMount:(NSDictionary*)mount_paths {
    // do nothing if there is already an active installer
    if (installer)
        return;
    
    NSString* path = [mount_paths objectForKey:@"path"];
    
    NSString* localized_mount_name = [[NSFileManager defaultManager] displayNameAtPath:path];
    if (!localized_mount_name)
        localized_mount_name = [path lastPathComponent];
    
    NSAlert* alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[NSString stringWithFormat:@"Do you wish to install Riven from the disc \"%@\"?", localized_mount_name]];
    [alert setInformativeText:@"Riven needs to be installed on your computer before you can play. You will not need to insert your disc after this."];
    
    [alert addButtonWithTitle:@"Install"];
    [alert addButtonWithTitle:@"Cancel"];
    
    [alert beginSheetModalForWindow:[self window] modalDelegate:self didEndSelector:@selector(_didEndOfferToInstallAlert:returnCode:contextInfo:) contextInfo:[mount_paths retain]];
}

- (IBAction)cancelInstallation:(id)sender {
    [NSApp abortModal];
}

#pragma mark removable media

- (BOOL)_checkMediaContent:(NSString*)path {    
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
    
    // if there's no Data directory, we're not interested
    if (!data_path)
        return NO;
    
    // check for the usual suspects
    NSArray* data_archives = [[BZFSContentsOfDirectory(data_path, &error) filteredArrayUsingPredicate:[RXEditionManager dataArchiveFilenamePredicate]]
                              sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
    if ([data_archives count] == 0)
        return NO;
    
    // if there is an Assets1 directory, it must contain sound archives
    NSArray* assets_archives = nil;
    if (assets_path) {
        assets_archives = [[BZFSContentsOfDirectory(assets_path, &error) filteredArrayUsingPredicate:[RXEditionManager soundsArchiveFilenamePredicate]]
                           sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
        if ([assets_archives count] == 0)
            return NO;
    }
    
    // if there is an All directory, it will contain data archives
    NSArray* all_archives = nil;
    if (all_path) {
        all_archives = [[BZFSContentsOfDirectory(all_path, &error) filteredArrayUsingPredicate:[RXEditionManager dataArchiveFilenamePredicate]]
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
    if (installer)
        [self performSelectorOnMainThread:@selector(_stopWaitingForDisc:) withObject:mount_paths waitUntilDone:NO];
    else
        [self performSelectorOnMainThread:@selector(_offerToInstallFromMount:) withObject:mount_paths waitUntilDone:NO];
    
    return YES;
}

- (void)_performMountScan:(NSString*)path {
    BOOL usable_mount = [self _checkMediaContent:path];
    if (!usable_mount && installer)
        [[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtPath:path];
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
