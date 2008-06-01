/* FSNSValue.h Copyright (c) 2003-2006 Philippe Mougin.   */
/*   This software is open source. See the license.  */  

#import <Foundation/Foundation.h>


@interface NSValue (FSNSValue) 

///////////////////////////////// USER METHODS /////////////////////////

// Common

- (id)clone;
- (NSString *)printString;

// NSPoint

- (NSRect)corner:(NSPoint)operand;
- (NSRect)extent:(NSPoint)operand;
- (float)x;
- (float)y;

// NSRange

+ (NSRange)rangeWithLocation:(unsigned int)location length:(unsigned int)length;
- (unsigned int)length;
- (unsigned int)location;

// NSRect

- (NSPoint)corner;
- (NSPoint)extent;
- (NSPoint)origin;

// NSSize

+ (NSSize)sizeWithWidth:(float)width height:(float)height;
- (float)height;
- (float)width;


@end
