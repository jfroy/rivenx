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
#import "Engine/RXEditionManagerWindowController.h"
#import "Engine/RXCardDescriptor.h"
#import "Engine/RXStack.h"


@interface RXEditionManager : NSObject {
    NSMutableDictionary* editions;
    NSMutableArray* edition_proxies;
    NSString* _patches_directory;
    
    RXEdition* current_edition;
    NSMutableDictionary* active_stacks;
    MHKArchive* _extras_archive;
    
    RXEditionManagerWindowController* _window_controller;
    BOOL _torn_down;
    
    OSSpinLock _valid_mount_paths_lock;
    NSMutableArray* _valid_mount_paths;
    NSMutableArray* _validated_mount_paths;
    NSString* _waiting_disc_name;
    
    NSString* _local_data_store;
    
    NSMutableDictionary* _settings;
}

+ (RXEditionManager*)sharedEditionManager;

- (void)tearDown;

- (void)showEditionManagerWindow;

- (NSArray*)editionProxies;
- (RXEdition*)editionForKey:(NSString*)editionKey;

- (RXEdition*)currentEdition;
- (BOOL)makeEditionCurrent:(RXEdition*)edition rememberChoice:(BOOL)remember error:(NSError**)error;

- (RXEdition*)defaultEdition;
- (void)setDefaultEdition:(RXEdition*)edition;
- (void)resetDefaultEdition;

- (NSString*)mountPathForDisc:(NSString*)disc waitingInModalSession:(NSModalSession)session;

- (void)ejectMountPath:(NSString*)mountPath;

- (RXSimpleCardDescriptor*)lookupCardWithKey:(NSString*)lookup_key;
- (uint16_t)lookupBitmapWithKey:(NSString*)lookup_key;
- (uint16_t)lookupSoundWithKey:(NSString*)lookup_key;

- (NSArray*)dataPatchArchivesForStackKey:(NSString*)stackKey error:(NSError**)error;

- (MHKArchive*)dataArchiveWithFilename:(NSString*)filename stackKey:(NSString*)stackKey error:(NSError**)error;
- (MHKArchive*)soundArchiveWithFilename:(NSString*)filename stackKey:(NSString*)stackKey error:(NSError**)error;
- (MHKArchive*)extrasArchive;

- (RXStack*)activeStackWithKey:(NSString*)stackKey;
- (RXStack*)loadStackWithKey:(NSString*)stackKey;

@end
