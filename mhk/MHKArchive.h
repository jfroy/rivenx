/*
 *  MHKArchive.h
 *  MHKKit
 *
 *  Created by Jean-Francois Roy on 09/04/2005.
 *  Copyright 2005-2010 MacStorm. All rights reserved.
 *
 */

#import <Foundation/Foundation.h>
#import <QuickTime/QuickTime.h>

#import <pthread.h>

#import <MHKKit/mohawk_core.h>
#import <MHKKit/mohawk_bitmap.h>

#import <MHKKit/MHKFileHandle.h>
#import <MHKKit/MHKAudioDecompression.h>


@interface MHKArchive : NSObject {
    NSURL* mhk_url;
    
    SInt16 forkRef;
    uint32_t archive_size;
    
    BOOL initialized;
    
    // global MHK parameters
    uint32_t resource_directory_absolute_offset;
    
    uint32_t type_table_count;
    MHK_type_table_entry* type_table;
    
    char* name_list;
    
    uint32_t file_table_count;
    MHK_file_table_entry* file_table;
    
    // processed information
    NSMutableDictionary* file_descriptor_arrays;
    NSMutableDictionary* file_descriptor_trees;
    NSMutableDictionary* file_descriptor_name_maps;
    
    // opened file count
    uint32_t __open_files;
    pthread_mutex_t __open_files_mutex;
    
    // cached descriptors
    pthread_rwlock_t __cached_sound_descriptors_rwlock;
    NSMutableDictionary* __cached_sound_descriptors;
}

// designated initializer
- (id)initWithURL:(NSURL*)url error:(NSError**)errorPtr;

// convenience initializers
- (id)initWithPath:(NSString*)path error:(NSError**)errorPtr;

// accessors
- (NSURL*)url;
- (NSArray*)resourceTypes;

// MHKArchive is KVO-compliant for all resource types as keys, read-only

// resource accessors
- (NSDictionary*)resourceDescriptorWithResourceType:(NSString*)type ID:(uint16_t)resourceID;
- (MHKFileHandle*)openResourceWithResourceType:(NSString*)type ID:(uint16_t)resourceID;
- (NSData*)dataWithResourceType:(NSString*)type ID:(uint16_t)resourceID;

// resource by-name accessors
- (NSDictionary*)resourceDescriptorWithResourceType:(NSString*)type name:(NSString*)name;
- (MHKFileHandle*)openResourceWithResourceType:(NSString*)type name:(NSString*)name;
- (NSData*)dataWithResourceType:(NSString*)type name:(NSString*)name;

@end

@interface MHKArchive (MHKArchiveQuickTimeAdditions)
- (Movie)movieWithID:(uint16_t)movieID error:(NSError**)errorPtr;
@end

@interface MHKArchive (MHKArchiveWAVAdditions)
- (NSDictionary*)soundDescriptorWithID:(uint16_t)soundID error:(NSError**)error;
- (MHKFileHandle*)openSoundWithID:(uint16_t)soundID error:(NSError**)error;
- (id <MHKAudioDecompression>)decompressorWithSoundID:(uint16_t)soundID error:(NSError**)error;
@end

@interface MHKArchive (MHKArchiveBitmapAdditions)
- (NSDictionary*)bitmapDescriptorWithID:(uint16_t)bitmapID error:(NSError**)errorPtr;
- (BOOL)loadBitmapWithID:(uint16_t)bitmapID buffer:(void*)pixels format:(MHK_BITMAP_FORMAT)format error:(NSError**)errorPtr;
@end
