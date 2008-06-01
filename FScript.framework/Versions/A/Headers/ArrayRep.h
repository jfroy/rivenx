/* ArrayRep.h Copyright (c) 1998-2006 Philippe Mougin.  */
/*   This software is open source. See the license.  */  

#import <Foundation/Foundation.h>

@class Array;
@class ArrayRepId;
@class Block;

enum ArrayRepType {FS_ID, DOUBLE, EMPTY, BOOLEAN, FETCH_REQUEST}; // These enums are used in a char instance variable of Array, so there must be less than 127 possible values (!) or char will have to be changed to something larger.

@protocol ArrayRepOptionalMethods
- (unsigned)count;
- (NSString *)descriptionLimited:(unsigned)nbElem;
- (Array *) distinctId; 
- (unsigned)indexOfObject:(id)anObject inRange:(NSRange)range identical:(BOOL)identical;
- indexWithArray:(Array *)index;
- (id)operator_backslash:(Block*)bl; // precond: ![bl isProxy] && count != 0 
- (void)removeLastElem;
- (void)removeElemAtIndex:(unsigned)index;
- (Array *)replicateWithArray:(Array *)operand;
- (Array *)reverse;
- (Array *)rotatedBy:(NSNumber *)operand;
- (Array *)sort;
- (NSArray *)subarrayWithRange:(NSRange)range;
@end

@protocol ArrayRep <NSCopying> 

- (ArrayRepId *) asArrayRepId;
- (enum ArrayRepType)repType;

@end
