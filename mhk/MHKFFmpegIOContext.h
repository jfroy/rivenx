// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import <Foundation/NSObject.h>

struct AVIOContext;
@class MHKFileHandle;

@interface MHKFFmpegIOContext : NSObject

@property(nonatomic, readonly) MHKFileHandle* fileHandle;
@property(nonatomic, readonly) struct AVIOContext* avioc;

- (instancetype)initWithFileHandle:(MHKFileHandle*)fileHandle
                             error:(NSError**)outError NS_DESIGNATED_INITIALIZER;

@end
