// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "Base/RXBase.h"

@class MHKArchive;
@class NSPredicate;

@interface RXArchiveManager : NSObject

+ (RXArchiveManager*)sharedArchiveManager;

+ (NSPredicate*)anyArchiveFilenamePredicate;
+ (NSPredicate*)dataArchiveFilenamePredicate;
+ (NSPredicate*)soundsArchiveFilenamePredicate;
+ (NSPredicate*)extrasArchiveFilenamePredicate;

// NOTE: these methods return the archives sorted in the order they should be searched; code should always
// forward-iterate the returned array

- (NSArray*)dataArchivesForStackKey:(NSString*)stack_key error:(NSError**)error;
- (NSArray*)soundArchivesForStackKey:(NSString*)stack_key error:(NSError**)error;
- (MHKArchive*)extrasArchive:(NSError**)error;

@end
