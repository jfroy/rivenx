/* FSNSDate.h Copyright (c) 1998-2006 Philippe Mougin.  */
/*   This software is open source. See the license.  */  

#import <Foundation/Foundation.h>
 
@class FSBoolean;

@interface NSDate (FSNSDate)

////////////////////////// USER METHODS

+ (NSDate *) now;

- (id)clone;
- (id)max:(NSDate *)operand;
- (id)min:(NSDate *)operand;
- (FSBoolean *)operator_greater:(NSDate *)operand;
- (FSBoolean *)operator_greater_equal:(NSDate *)operand;
- (NSNumber *) operator_hyphen:(NSDate *)operand;
- (FSBoolean *)operator_less:(NSDate *)operand;  
- (FSBoolean *)operator_less_equal:(NSDate *)operand;

@end
