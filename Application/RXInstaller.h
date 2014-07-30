// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "Base/RXBase.h"

@protocol RXInstaller <NSObject>

@property (nonatomic, readonly) NSString* stage;
@property (nonatomic, readonly) double progress;

- (void)runWithCompletionBlock:(void(^)(BOOL success, NSError* error))block;
- (void)cancel;

@end
