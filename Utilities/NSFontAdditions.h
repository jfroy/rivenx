//
//  NSFontAdditions.h
//  rivenx
//
//  Created by Jean-Francois Roy on 05/09/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface NSFont (NSFontAdditions)
+ (NSFont *)fontWithURL:(NSURL *)fontURL name:(NSString *)fontName size:(float)fontSize;
@end
