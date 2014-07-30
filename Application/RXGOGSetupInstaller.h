// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "Application/RXInstaller.h"

@interface RXGOGSetupInstaller : NSObject <RXInstaller>

- (instancetype)initWithGOGSetupURL:(NSURL*)url;

@end
