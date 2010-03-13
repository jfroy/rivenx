//
//  RXArchiveManager.h
//  rivenx
//
//  Created by Jean-Francois Roy on 02/02/2008.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MHKKit/MHKKit.h>


@interface RXArchiveManager : NSObject {
    NSString* patches_directory;
    
    MHKArchive* extras_archive;
    
    NSString* local_data_store;
}

+ (RXArchiveManager*)sharedArchiveManager;

+ (NSPredicate*)anyArchiveFilenamePredicate;
+ (NSPredicate*)dataArchiveFilenamePredicate;
+ (NSPredicate*)soundsArchiveFilenamePredicate;
+ (NSPredicate*)extrasArchiveFilenamePredicate;

- (NSArray*)dataArchivesForStackKey:(NSString*)stack_key error:(NSError**)error;
- (NSArray*)soundArchivesForStackKey:(NSString*)stack_key error:(NSError**)error;
- (MHKArchive*)extrasArchive:(NSError**)error;

- (NSArray*)dataPatchArchivesForStackKey:(NSString*)stackKey error:(NSError**)error;

@end
