//
//  RXWindow.h
//  rivenx
//
//  Created by Jean-Francois Roy on 30/01/2010.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import <AppKit/NSWindow.h>


@interface RXWindow : NSWindow
{
    BOOL constrainingToScreenSuspended;
}

@property BOOL constrainingToScreenSuspended;

@end
