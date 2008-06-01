
/* FSNSObject.m Copyright (c) 1998-2006 Philippe Mougin.  */
/*   This software is open source. See the license.  */

#ifndef __FScript_FSNSObject_H__
#define __FScript_FSNSObject_H__

#import <Foundation/Foundation.h>

@class Array, FSBoolean, NSString, NSConnection, Block;


@protocol FSNSObject

// USER METHODS 
- (id)applyBlock:(Block *)block;
- (id)classOrMetaclass;
- (Array *)enlist;
- (Array *)enlist:(NSNumber *)operand; 
- (id)operator_equal:(id)operand;
- (id)operator_tilde_equal:(id)operand;
- (FSBoolean *)operator_equal_equal:(id)operand;
- (FSBoolean *)operator_tilde_tilde:(id)operand; 
- (NSString *)printString;
- (void)throw;

@end

@interface NSObject(FSNSObject) <FSNSObject>

// USER METHODS

- (id)applyBlock:(Block *)block;
- (Array *)enlist;
- (Array *)enlist:(NSNumber *)operand; 
- (id)operator_equal:(id)operand;
- (FSBoolean *)operator_equal_equal:(id)operand;
- (id)operator_tilde_equal:(id)operand;  
- (FSBoolean *)operator_tilde_tilde:(id)operand;
- (NSString *)printString;
- (void)save; // may raise
- (void)save:(NSString *)operand; // may raise
- (void)throw;
- (NSConnection *)vend:(NSString *)operand;

// OTHER METHODS

+ (id)classOrMetaclass;
+ replacementObjectForCoder:(NSCoder *)encoder;

- (id)classOrMetaclass;


@end

#endif /* __FScript_FSNSObject_H__ */
