//
//  RXEditionManager.h
//  rivenx
//
//  Created by Jean-Francois Roy on 02/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MHKKit/MHKKit.h>
#import <libkern/OSAtomic.h>

#import "Engine/RXEdition.h"
#import "Engine/RXCardDescriptor.h"
#import "Engine/RXStack.h"


@interface RXEditionManager : NSObject {
    NSMutableDictionary* editions;
    NSMutableArray* edition_proxies;
    NSString* _patches_directory;
    
    RXEdition* current_edition;
    NSMutableDictionary* active_stacks;
    MHKArchive* _extras_archive;
    
    OSSpinLock _valid_mount_paths_lock;
    NSMutableArray* _valid_mount_paths;
    NSMutableArray* _validated_mount_paths;
    NSString* _waiting_disc_name;
    
    NSString* _local_data_store;
    
    NSMutableDictionary* _settings;
    
    BOOL _torn_down;
}

+ (RXEditionManager*)sharedEditionManager;

+ (NSPredicate*)dataArchiveFilenamePredicate;
+ (NSPredicate*)soundsArchiveFilenamePredicate;
+ (NSPredicate*)extrasArchiveFilenamePredicate;

- (void)tearDown;

- (NSArray*)editionProxies;
- (RXEdition*)editionForKey:(NSString*)editionKey;

- (RXEdition*)currentEdition;
- (BOOL)makeEditionCurrent:(RXEdition*)edition rememberChoice:(BOOL)remember error:(NSError**)error;

- (RXEdition*)defaultEdition;
- (void)setDefaultEdition:(RXEdition*)edition;
- (void)resetDefaultEdition;

- (NSArray*)dataArchivesForStackKey:(NSString*)stack_key error:(NSError**)error;
- (NSArray*)soundArchivesForStackKey:(NSString*)stack_key error:(NSError**)error;
- (MHKArchive*)extrasArchive:(NSError**)error;

- (NSArray*)dataPatchArchivesForStackKey:(NSString*)stackKey error:(NSError**)error;

- (RXStack*)activeStackWithKey:(NSString*)stackKey;
- (RXStack*)loadStackWithKey:(NSString*)stackKey;

@end
