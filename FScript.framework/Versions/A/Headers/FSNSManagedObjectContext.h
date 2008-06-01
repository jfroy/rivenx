/* FSNSManagedObjectContext.h Copyright (c) 2005-2006 Philippe Mougin.  */
/*   This software is open source. See the license.  */ 
 
#import <Cocoa/Cocoa.h>

@class System;

@interface NSManagedObjectContext(FSNSManagedObjectContext)

- (void)inspectWithSystem:(System *)system;

@end

