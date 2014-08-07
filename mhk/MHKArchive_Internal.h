// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "mhk/MHKArchive.h"

#import "mhk/mohawk_core.h"

@interface MHKArchive () {
 @package
  // file descriptor for IO
  int _fd;

  // cached sound descriptors
  NSMutableDictionary* _sdescs;
}

@end
