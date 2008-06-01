/*   Array.h Copyright (c) 1998-2006 Philippe Mougin.     */
/*   This software is open source. See the license.       */


#import <Foundation/Foundation.h>
#import "FSNSObject.h"
#import "ArrayRep.h"
#import "FSNSArray.h"
#import "FSNSMutableArray.h"

@class NSTableView, Block, System ;
 
@interface Array: NSMutableArray
{
  unsigned retainCount;
  enum ArrayRepType type;
  id rep;  // internal representation
} 


///////////////////////////////////// USER METHODS

- (id)at:(id)index put:(id)elem;
- (Array *)distinctId;
- (BOOL)isEqual:(id)anObject;
- (Array *)replicate:(NSArray *)operand;
- (Array *)reverse;
- (Array *)rotatedBy:(NSNumber *)operand;
- (Array *)sort;

///////////////////////////////////// OTHER METHODS

+ (void) initialize;
+ (double) maxCount;
+ (id)arrayWithObject:(id)anObject;
+ (id)arrayWithObjects:(id *)objects count:(unsigned)count;

- (void)addObject:(id)anObject;
- (NSArray *)arrayByAddingObject:(id)anObject;
- (NSArray *)arrayByAddingObjectsFromArray:(NSArray *)otherArray;
- (BOOL)containsObject:(id)anObject;
- copyWithZone:(NSZone *)zone;
- (unsigned)count;
- (void)dealloc;
- (NSString *)description;
- (NSString *)descriptionWithLocale:(NSDictionary *)locale;
- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(unsigned)level;
- (unsigned)indexOfObject:(id)anObject;
- (unsigned)indexOfObject:(id)anObject inRange:(NSRange)range;
- (unsigned)indexOfObjectIdenticalTo:(id)anObject;
- (unsigned)indexOfObjectIdenticalTo:(id)anObject inRange:(NSRange)range;
- init;
- initWithCapacity:(unsigned)aNumItems;  // designated initializer
- initWithObject:(id)object;
- initWithObjects:(id *)objects count:(unsigned)nb;
- (void)insertObject:anObject atIndex:(unsigned)index;
- (BOOL)isEqualToArray:(NSArray *)anArray;
- mutableCopyWithZone:(NSZone *)zone;
- objectAtIndex:(unsigned)index;
- (NSEnumerator *)objectEnumerator;
- (void)removeLastObject;
- (void)removeObjectAtIndex:(unsigned)index;
- (void)replaceObjectAtIndex:(unsigned int)index withObject:(id)anObject;
- (id)retain;
- (unsigned int)retainCount;
- (void)release;
- (NSEnumerator *)reverseObjectEnumerator;
- (void)setArray:(NSArray *)operand;
- (NSArray *)subarrayWithRange:(NSRange)range; // returns an instance of Array.

@end
