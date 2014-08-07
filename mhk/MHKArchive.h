// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import <Foundation/NSArray.h>
#import <Foundation/NSError.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

@class MHKFileHandle;

@interface MHKResourceDescriptor : NSObject
@property (nonatomic, readonly) uint16_t ID;
@property (nonatomic, readonly) uint32_t index;
@property (nonatomic, readonly) NSString* name;
@property (nonatomic, readonly) off_t offset;
@property (nonatomic, readonly) off_t length;
@end

@interface MHKArchive : NSObject

@property (nonatomic, readonly) NSURL* url;
@property (nonatomic, readonly) NSArray* resourceTypes;

- (instancetype)initWithURL:(NSURL*)url error:(NSError**)outError NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithPath:(NSString*)path error:(NSError**)outError;

- (NSArray*)resourceDescriptorsForType:(NSString*)type;

// resource accessors
- (MHKResourceDescriptor*)resourceDescriptorWithResourceType:(NSString*)type ID:(uint16_t)resourceID;
- (MHKFileHandle*)openResourceWithResourceType:(NSString*)type ID:(uint16_t)resourceID;
- (NSData*)dataWithResourceType:(NSString*)type ID:(uint16_t)resourceID;

// resource by-name accessors
- (MHKResourceDescriptor*)resourceDescriptorWithResourceType:(NSString*)type name:(NSString*)name;
- (MHKFileHandle*)openResourceWithResourceType:(NSString*)type name:(NSString*)name;
- (NSData*)dataWithResourceType:(NSString*)type name:(NSString*)name;

@end
