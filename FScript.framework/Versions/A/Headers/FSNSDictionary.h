/* FSNSDictionary.h Copyright (c) 2000-2006 Philippe Mougin.  */
/*   This software is open source. See the license.  */ 
 
#import <Foundation/Foundation.h>

@class System;

@interface NSDictionary(FSNSDictionary)

- (void)inspectIn:(System *)system;  // use inspectWithSystem: instead
- (void)inspectWithSystem:(System *)system;
- (void)inspectIn:(System *)system with:(NSArray *)blocks; // use inspectWithSystem:blocks: instead
- (void)inspectWithSystem:(System *)system blocks:(NSArray *)blocks;
- (NSString *)printString;

@end
