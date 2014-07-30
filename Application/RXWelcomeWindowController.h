// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import <AppKit/NSWindowController.h>
#import <AppKit/NSSavePanel.h>

#import "Application/RXMediaInstaller.h"

@interface RXWelcomeWindowController
    : NSWindowController<RXMediaInstallerMediaProviderProtocol, NSOpenSavePanelDelegate>
@end
