// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "mhk/MHKFileHandle.h"

@class MHKResourceDescriptor;

@interface MHKFileHandle ()

- (instancetype)initWithArchive:(MHKArchive*)archive
                         length:(off_t)length
                  archiveOffset:(off_t)archiveOffset
                       ioOffset:(off_t)ioOffset NS_DESIGNATED_INITIALIZER;

@end
