/* FSNSString.h Copyright (c) 1998-2006 Philippe Mougin.  */
/*   This software is open source. See the license.  */  

#ifndef __FScript_FSNSString_H__
#define __FScript_FSNSString_H__

#import <Foundation/Foundation.h>

@class Block;
@class Array;
@class FSBoolean;

@interface NSString (FSNSString)

- (Array *) asArray;
- (Array *) asArrayOfCharacters;
- (Block *) asBlock;
- (Block *) asBlockOnError:(Block *)errorBlock;
- (id) asClass;
- (NSDate *) asDate;
- (NSString *)at:(NSNumber *)operand;
- (NSString *)clone;
- (id) connect;
- (id) connectOnHost:(NSString *)operand;
- (NSString *)max:(NSString *)operand;
- (NSString *)min:(NSString *)operand;
- (NSString *)operator_plus_plus:(NSString *)operand;
- (FSBoolean *)operator_greater:(NSString *)operand;
- (FSBoolean *)operator_greater_equal:(NSString *)operand;
- (FSBoolean *)operator_less:(id)operand;
- (FSBoolean *)operator_less_equal:(NSString *)operand;
- (NSString *)printString;
- (NSString *)reverse;
- (NSNumber *)size;

@end

#endif /* __FScript_FSNSString_H__ */
