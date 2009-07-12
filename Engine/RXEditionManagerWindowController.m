//
//  RXEditionManagerWindowController.m
//  rivenx
//
//  Created by Jean-Francois Roy on 02/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "RXEditionManagerWindowController.h"
#import "RXEditionManager.h"
#import "RXEditionInstaller.h"

#import "ImagePreviewCell.h"


@implementation RXEditionManagerWindowController

- (void)awakeFromNib {
    ImagePreviewCell* cell = [[[ImagePreviewCell alloc] init] autorelease];
    [[_editionsTableView tableColumnWithIdentifier:@"editions"] setDataCell:cell];
    
    [_editionsTableView setTarget:self];
    [_editionsTableView setDoubleAction:@selector(choose:)];
    
    [self willChangeValueForKey:@"thumbnailHeight"];
    _thumbnailSize = NSMakeSize(64.0, 64.0);
    [self didChangeValueForKey:@"thumbnailHeight"];
    
    NSSortDescriptor* sd = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES];
    [_editionsArrayController setSortDescriptors:[NSArray arrayWithObject:sd]];
    [sd release];
    
    [_editionsArrayController setContent:[[RXEditionManager sharedEditionManager] editionProxies]];
}

- (void)dealloc {
    [super dealloc];
}

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    id value = [cell objectValue];
    
    // FIXME: use something else than the application icon
    NSImage* icon = [NSImage imageNamed:@"NSApplicationIcon"];
    [icon setSize:_thumbnailSize];
    
    [cell setTitle:[value valueForKey:@"name"]];
    if ([[value valueForKey:@"isInstalled"] boolValue]) {
        if ([[value valueForKey:@"isFullInstalled"] boolValue])
            [cell setSubTitle:NSLocalizedStringFromTable(@"FULL_INSTALLED", @"Editions", NULL)];
        else
            [cell setSubTitle:NSLocalizedStringFromTable(@"INSTALLED", @"Editions", NULL)];
    } else if ([[value valueForKey:@"mustBeInstalled"] boolValue])
        [cell setSubTitle:NSLocalizedStringFromTable(@"MUST_INSTALL", @"Editions", NULL)];
    else [cell setSubTitle:NSLocalizedStringFromTable(@"NOT_INSTALLED", @"Editions", NULL)];
    [cell setImage:icon];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return _thumbnailSize.height + 9.0; // The extra space is padding around the cell
}

- (CGFloat)thumbnailHeight {
    return _thumbnailSize.height + 9.0;
}

- (void)windowWillClose:(NSNotification *)notification {
    if (_pickedEdition == nil)
        [NSApp terminate:self];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
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

- (void)_rememberChoiceAlertDidEnd:(NSAlert*)alert returnCode:(int)returnCode contextInfo:(void*)contextInfo {
    BOOL remember = (returnCode == NSAlertFirstButtonReturn) ? YES : NO;
    
    // dismiss the alert sheet and close the edition manager window
    [[alert window] orderOut:self];
    [self close];
    
    // we're done with the alert
    [alert release];
    
    // set the gears into motion
    // FIXME: handle errors
    if (!remember)
        [[RXEditionManager sharedEditionManager] resetDefaultEdition];
    
    NSError* error;
    if (![[RXEditionManager sharedEditionManager] makeEditionCurrent:_pickedEdition rememberChoice:remember error:&error]) {
        if ([error code] == kRXErrEditionCantBecomeCurrent && [error domain] == RXErrorDomain) {
            error = [NSError errorWithDomain:[error domain] code:[error code] userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                [NSString stringWithFormat:@"Riven X cannot make \"%@\" the current edition because it is not installed.", [_pickedEdition valueForKey:@"name"]], NSLocalizedDescriptionKey,
                @"You need to install this edition by using the Edition Manager.", NSLocalizedRecoverySuggestionErrorKey,
                [NSArray arrayWithObjects:@"Install", @"Quit", nil], NSLocalizedRecoveryOptionsErrorKey,
                [NSApp delegate], NSRecoveryAttempterErrorKey,
                error, NSUnderlyingErrorKey,
            nil]];
        }
        
        [NSApp presentError:error];
    }
}

- (void)_makeEditionCurrent:(RXEdition*)ed {    
    // configure the alert to ask the user if they wish RX to remember their choice
    NSAlert* rememberEditionChoiceAlert = [[NSAlert alloc] init];
    [rememberEditionChoiceAlert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"REMEMBER_CHOICE", @"Editions", NULL), [ed valueForKey:@"name"]]];
    [rememberEditionChoiceAlert setInformativeText:NSLocalizedStringFromTable(@"REMEMBER_CHOICE_INFO", @"Editions", NULL)];
    [rememberEditionChoiceAlert addButtonWithTitle:NSLocalizedStringFromTable(@"REMEMBER_CHOICE_USE", @"Editions", NULL)];
    [rememberEditionChoiceAlert addButtonWithTitle:NSLocalizedStringFromTable(@"REMEMBER_CHOICE_DONT_USE", @"Editions", NULL)];
    
    // save a weak reference to the selected edition
    _pickedEdition = ed;
    
    // begin the alert as a sheet
    [rememberEditionChoiceAlert beginSheetModalForWindow:[self window] modalDelegate:self didEndSelector:@selector(_rememberChoiceAlertDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

- (void)_initializeInstallationUI:(RXEditionInstaller*)installer {
    [_installingTitleField setStringValue:NSLocalizedStringFromTable(@"INSTALLER_PREPARING", @"Editions", NULL)];
    [_installingStatusField setStringValue:@""];
    [_installingProgress setMinValue:0.0];
    [_installingProgress setMaxValue:1.0];
    [_installingProgress setDoubleValue:0.0];
    [_installingProgress setIndeterminate:YES];
    [_installingProgress setUsesThreadedAnimation:YES];
    [_installingProgress startAnimation:self];
}

- (void)_minimumInstallForUser:(RXEdition*)ed {
    // create an installer
    RXEditionInstaller* installer = [[RXEditionInstaller alloc] initWithEdition:ed];
    
    // setup the basic installation UI
    [self _initializeInstallationUI:installer];
    
    // show the installation panel
    [NSApp beginSheet:_installingSheet modalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:installer];
    _installerSession = [NSApp beginModalSessionForWindow:_installingSheet];
    
    // observe the installer
    [installer addObserver:self forKeyPath:@"progress" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:NULL];
    [_installingTitleField bind:@"value" toObject:installer withKeyPath:@"stage" options:nil];
    
    // install away
    BOOL didInstall = [installer minimalUserInstallInModalSession:_installerSession error:NULL];
    
    // dismiss the sheet
    [NSApp endModalSession:_installerSession];
    _installerSession = NULL;
    
    [NSApp endSheet:_installingSheet returnCode:0];
    [_installingSheet orderOut:self];
    [_installingProgress stopAnimation:self];
    
    // we're done with the installer
    [_installingTitleField unbind:@"value"];
    [installer removeObserver:self forKeyPath:@"progress"];
    [installer release];
    
    // if the edition was installed, make it current
    if (didInstall)
        [self _makeEditionCurrent:ed];
}

- (void)_fullInstallForUser:(RXEdition*)ed {
    // create an installer
    RXEditionInstaller* installer = [[RXEditionInstaller alloc] initWithEdition:ed];
    
    // setup the basic installation UI
    [self _initializeInstallationUI:installer];
    
    // show the installation panel
    [NSApp beginSheet:_installingSheet modalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:installer];
    _installerSession = [NSApp beginModalSessionForWindow:_installingSheet];
    
    // observe the installer
    [installer addObserver:self forKeyPath:@"progress" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:NULL];
    [_installingTitleField bind:@"value" toObject:installer withKeyPath:@"stage" options:nil];
    
    // install away
    BOOL didInstall = [installer fullUserInstallInModalSession:_installerSession error:NULL];
    
    // dismiss the sheet
    [NSApp endModalSession:_installerSession];
    _installerSession = NULL;
    
    [NSApp endSheet:_installingSheet returnCode:0];
    [_installingSheet orderOut:self];
    [_installingProgress stopAnimation:self];
    
    // we're done with the installer
    [_installingTitleField unbind:@"value"];
    [installer removeObserver:self forKeyPath:@"progress"];
    [installer release];
    
    // if the edition was installed, make it current
    if (didInstall)
        [self _makeEditionCurrent:ed];
}

- (void)_mustInstallAlertDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo {
    [[alert window] orderOut:self];
    
    if (returnCode == NSAlertAlternateReturn)
        return;
    else if (returnCode == NSAlertDefaultReturn)
        [self _minimumInstallForUser:contextInfo];
}

- (void)_displayMustInstallSheet:(RXEdition*)ed {
    NSAlert* alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"INSTALL_ALERT_TITLE", @"Editions", NULL), [ed valueForKey:@"name"]] 
                                     defaultButton:NSLocalizedStringFromTable(@"INSTALL_ALERT_INSTALL_SELF", @"Editions", NULL) 
                                   alternateButton:NSLocalizedStringFromTable(@"INSTALL_ALERT_DONT_INSTALL", @"Editions", NULL) 
                                       otherButton:NSLocalizedStringFromTable(@"INSTALL_ALERT_INSTALL_ALL", @"Editions", NULL) 
                         informativeTextWithFormat:NSLocalizedStringFromTable(@"INSTALL_ALERT_MESSAGE", @"Editions", NULL)];
    [alert beginSheetModalForWindow:[self window] modalDelegate:self didEndSelector:@selector(_mustInstallAlertDidEnd:returnCode:contextInfo:) contextInfo:ed];
}

- (IBAction)choose:(id)sender {
    RXEdition* ed = [[_editionsArrayController selection] valueForKey:@"edition"];
    if (ed == NSNoSelectionMarker)
        return;
    
    if (![ed canBecomeCurrent] && [ed mustBeInstalled])
        [self _displayMustInstallSheet:ed];
    else if ([ed canBecomeCurrent])
        [self _makeEditionCurrent:ed];
}

- (IBAction)install:(id)sender {
    RXEdition* ed = [[_editionsArrayController selection] valueForKey:@"edition"];
    [self performSelector:@selector(_fullInstallForUser:) withObject:ed afterDelay:0.0];
}

- (IBAction)cancelInstallation:(id)sender {
    [NSApp abortModal];
}

@end
