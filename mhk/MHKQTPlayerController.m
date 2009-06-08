//
//  MHKQTPlayerController.m
//  MHKKit
//
//  Created by Jean-Francois Roy on 09/04/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import "MHKQTPlayerController.h"


@implementation MHKQTPlayerController

+ (BOOL)accessInstanceVariablesDirectly {
    return NO;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
    if([key isEqualToString:@"archive"]) return NO;
    
    return [super automaticallyNotifiesObserversForKey:key];
}

- (void)awakeFromNib {
    [qtView setMovie:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [mediaListDrawer open];
}

- (void)dealloc {
    [qtView setMovie:nil];
    [archive release];
    [super dealloc];
}

- (id)archive {
    return archive;
}

- (IBAction)openDocument:(id)sender {
    // Let's select a document!
    
    // First we setup our dialog
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseFiles:YES];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setAllowsMultipleSelection:NO];
    
    int returnCode = [openPanel runModalForTypes:[NSArray arrayWithObject:@"mhk"]];
    if(returnCode == NSOKButton) {
        [self application:NSApp openFile:[[openPanel filenames] objectAtIndex:0]];
    }
}

- (IBAction)saveDocumentAs:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes:[NSArray arrayWithObject:@"mov"]];
    [panel setAllowsOtherFileTypes:YES];
    [panel setCanSelectHiddenExtension:YES];
    
    int result = [panel runModalForDirectory:nil file:[[[archive valueForKey:@"tMOV"] objectAtIndex:[movieTableView selectedRow]] objectForKey:@"Name"]];
    if (result == NSOKButton) {
        NSDictionary *dict = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:QTMovieFlatten];
        [[qtView movie] writeToFile:[panel filename] withAttributes:dict];
    }
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename {
    NSError *error = nil;
    
    [self willChangeValueForKey:@"archive"];
    id old_archive = archive;
    archive = [[MHKArchive alloc] initWithPath:filename error:&error];
    [old_archive release];
    [self didChangeValueForKey:@"archive"];
    
    if(error) [NSApp presentError:error];
    return (archive) ? YES : NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    int selected_row = [[aNotification object] selectedRow];
    NSError *error = nil;
    
    if(selected_row == -1) {
        [qtView setMovie:nil];
    } else {
        QTMovie *qtMovie = nil;
        
        // get the movie
        NSDictionary *descriptor = [[archive valueForKey:@"tMOV"] objectAtIndex:selected_row];
        Movie aMovie = [archive movieWithID:[[descriptor objectForKey:@"ID"] unsignedShortValue] error:&error];
        if(error) [NSApp presentError:error];
        else {
            qtMovie = [QTMovie movieWithQuickTimeMovie:aMovie disposeWhenDone:YES error:&error];
            MoviesTask(aMovie, 0);
        }
        
        // set the movie
        if(error) [NSApp presentError:error];
        [qtView setMovie:qtMovie];
    }
    
    [qtView setNeedsDisplay:YES];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if([menuItem action] == @selector(saveDocumentAs:)) {
        return [qtView movie] != nil;
    }
    
    return YES;
}

@end
