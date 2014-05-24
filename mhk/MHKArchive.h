/*
 *  MHKArchive.h
 *  MHKKit
 *
 *  Created by Jean-Francois Roy on 09/04/2005.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#import <pthread.h>
#import <CoreServices/CoreServices.h>

#import <MHKKit/mohawk_core.h>

@class MHKFileHandle;

@interface MHKArchive : NSObject {
  NSURL* mhk_url;

  FSIORefNum forkRef;
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
