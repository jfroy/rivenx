//
//  MHKQTPlayerController.m
//  MHKKit
//
//  Created by Jean-Francois Roy on 09/04/2005.
//  Copyright 2005-2012 MacStorm. All rights reserved.
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

- (BOOL)application:(NSApplication *)application openFile:(NSString *)filename {
    NSError *error = nil;
    
    [self willChangeValueForKey:@"archive"];
    id old_archive = archive;
    archive = [[MHKArchive alloc] initWithPath:filename error:&error];
    [old_archive release];
    [self didChangeValueForKey:@"archive"];
    
    if(error) [NSApp presentError:error];
    return (archive) ? YES : NO;
}

- (IBAction)openDocument:(id)sender {
    // Let's select a document!
    
    // First we setup our dialog
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseFiles:YES];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setAllowedFileTypes:[NSArray arrayWithObject:@"mhk"]];
    
    int returnCode = [openPanel runModal];
    if (returnCode == NSOKButton) {
        [self application:NSApp openFile:[[openPanel URL] path]];
    }
}

- (IBAction)saveDocumentAs:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes:[NSArray arrayWithObject:@"mov"]];
    [panel setAllowsOtherFileTypes:YES];
    [panel setCanSelectHiddenExtension:YES];
    [panel setNameFieldStringValue:[[[archive valueForKey:@"tMOV"] objectAtIndex:[movieTableView selectedRow]] objectForKey:@"Name"]];

    int result = [panel runModal];
    if (result == NSOKButton) {
        NSDictionary *dict = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:QTMovieFlatten];
        [[qtView movie] writeToFile:[[panel URL] path] withAttributes:dict error:nil];
    }
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

- (IBAction)setCurrentTime:(id)sender {
    QTTime time = QTMakeTime([[timeValueField stringValue] integerValue], [[timeBaseField stringValue] integerValue]);
    [[qtView movie] setCurrentTime:time];
}

- (IBAction)getCurrentTime:(id)sender {
    QTTime time = [[qtView movie] currentTime];
    [timeValueField setStringValue:[NSString stringWithFormat:@"%lld", time.timeValue]];
    [timeBaseField setStringValue:[NSString stringWithFormat:@"%ld", time.timeScale]];
}

@end
