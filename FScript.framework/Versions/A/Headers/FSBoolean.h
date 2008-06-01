/*   FSBoolean.h Copyright (c) 1998-2006 Philippe Mougin.  */
/*   This software is open source. See the license.  */  

#import "FSNSObject.h"

@class True;
@class False;
@class Block;

@interface FSBoolean : NSObject <NSCopying,NSCoding>
{}

+ (FSBoolean *) booleanWithBool:(BOOL)theBool;
+ (False *) fsFalse;
+ (True *)  fsTrue;
- (FSBoolean *)and:(Block *)operand;
- (id) autorelease;
- (FSBoolean *)clone;
- (id) copy;
- (id) copyWithZone:(NSZone *)zone;
- (unsigned) hash;
- (id) ifFalse:(Block *)falseBlock;
- (id) ifFalse:(Block *)falseBlock ifTrue:(Block *)trueBlock;
- (id) ifTrue:(Block *)trueBlock;
- (id) ifTrue:(Block *)trueBlock ifFalse:(Block *)falseBlock;
- (BOOL) isEqual:(id)object;
- (FSBoolean *)not;
- (FSBoolean *)operator_ampersand:(FSBoolean *)operand;
- (FSBoolean *)operator_bar:(FSBoolean *)operand;
- (FSBoolean *)operator_less:(id)operand;
- (NSNumber *)operator_plus:(id)operand;
- (FSBoolean *)or:(Block *)operand;
- (void) release;
- (id) retain;
- (unsigned int) retainCount;
@end

@interface True: FSBoolean
{}
@end

@interface False: FSBoolean
{}
@end
