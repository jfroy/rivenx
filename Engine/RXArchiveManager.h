//
//  RXArchiveManager.h
//  rivenx
//
//  Created by Jean-Francois Roy on 02/02/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"
#import <MHKKit/MHKKit.h>


@interface RXArchiveManager : NSObject {
    NSString* patches_directory;
    MHKArchive* extras_archive;
}

+ (RXArchiveManager*)sharedArchiveManager;

+ (NSPredicate*)anyArchiveFilenamePredicate;
+ (NSPredicate*)dataArchiveFilenamePredicate;
+ (NSPredicate*)soundsArchiveFilenamePredicate;
+ (NSPredicate*)extrasArchiveFilenamePredicate;

// NOTE: these methods return the archives sorted in the order they should be searched; code should always forward-iterate the returned array

- (NSArray*)dataArchivesForStackKey:(NSString*)stack_key error:(NSError**)error;
- (NSArray*)soundArchivesForStackKey:(NSString*)stack_key error:(NSError**)error;
- (MHKArchive*)extrasArchive:(NSError**)error;

@end
