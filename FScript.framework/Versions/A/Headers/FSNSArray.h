/* FSNSArray.h Copyright (c) 1998-2006 Philippe Mougin.  */
/*   This software is open source. See the license.  */  
#import <Foundation/Foundation.h>

@class Block, Array, System;
 
@interface NSArray(FSNSArray)

// User methods 
- (id)at:(id)index;
- (id)clone;
- (Array *)difference:(NSArray *)operand;
- (Array *)distinct;
- (Array *)distinctId;
- (Array *)index; 
- (void)inspectIn:(System *)system;  // use inspectWithSystem: instead
- (void)inspectWithSystem:(System *)system;
- (void)inspectIn:(System *)system with:(NSArray *)blocks; // use inspectWithSystem:blocks: instead
- (void)inspectWithSystem:(System *)system blocks:(NSArray *)blocks;
- (Array *)intersection:(NSArray *)operand;
- (id)operator_backslash:(Block*)operand;
- (id)operator_equal:(id)operand;
- (NSNumber *)operator_exclam:(id)anObject;
- (NSNumber *)operator_exclam_exclam:(id)anObject;
- (Array *)operator_greater_less:(id)operand;
- (Array *)operator_plus_plus:(NSArray *)operand;
- (id)operator_tilde_equal:(id)operand;
- (Array *)prefixes;
- (NSString *)printString;
- (Array *)replicate:(NSArray *)operand;
- (Array *)reverse;
- (Array *)rotatedBy:(NSNumber *)operand;
- (Array *)scan:(Block*)operand;
- (NSNumber *)size;
- (Array *)sort;
- (Array *)subpartsOfSize:(NSNumber *)operand;
- (Array *)transposedBy:(NSArray *)operand;
- (Array *)union:(NSArray *)operand;

@end
