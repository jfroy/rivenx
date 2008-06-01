/* FSNSSet.h Copyright (c) 2004-2006 Philippe Mougin.  */
/*   This software is open source. See the license.  */ 
 
#import <Foundation/Foundation.h>

@class System;

@interface NSSet(FSNSSet)

- (void)inspectIn:(System *)system;  // use inspectWithSystem: instead
- (void)inspectWithSystem:(System *)system;
- (void)inspectIn:(System *)system with:(NSArray *)blocks; // use inspectWithSystem:blocks: instead
- (void)inspectWithSystem:(System *)system blocks:(NSArray *)blocks;

@end
