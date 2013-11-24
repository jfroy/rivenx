//
//  RXWindow.m
//  rivenx
//
//  Created by Jean-Francois Roy on 30/01/2010.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "RXWindow.h"

@implementation RXWindow

@synthesize constrainingToScreenSuspended;

- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen*)screen
{
  if (constrainingToScreenSuspended)
    return frameRect;
  else
    return [super constrainFrameRect:frameRect toScreen:screen];
}

- (BOOL)canBecomeKeyWindow { return YES; }

- (BOOL)canBecomeMainWindow { return YES; }

@end
