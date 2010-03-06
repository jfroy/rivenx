//
//  RXEditionManager.h
//  rivenx
//
//  Created by Jean-Francois Roy on 02/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MHKKit/MHKKit.h>

#import "Engine/RXStack.h"


@interface RXEditionManager : NSObject {
    NSString* patches_directory;
    
    NSMutableDictionary* active_stacks;
    MHKArchive* extras_archive;
    
    NSString* local_data_store;
}

+ (RXEditionManager*)sharedEditionManager;

+ (NSPredicate*)dataArchiveFilenamePredicate;
+ (NSPredicate*)soundsArchiveFilenamePredicate;
+ (NSPredicate*)extrasArchiveFilenamePredicate;

- (NSArray*)dataArchivesForStackKey:(NSString*)stack_key error:(NSError**)error;
- (NSArray*)soundArchivesForStackKey:(NSString*)stack_key error:(NSError**)error;
- (MHKArchive*)extrasArchive:(NSError**)error;

- (NSArray*)dataPatchArchivesForStackKey:(NSString*)stackKey error:(NSError**)error;

- (RXStack*)activeStackWithKey:(NSString*)stackKey;
- (RXStack*)loadStackWithKey:(NSString*)stackKey;

@end
