//  FSKVCoding.h Copyright (c) 2002 Joerg Garbers.
//  This software is open source. See the license.

#import <Foundation/Foundation.h>

enum fskvFilterType {attributeKeys=0,toOneRelationshipKeys,toManyRelationshipKeys,fskvUnclassifiedRelationshipKeys};          
@interface NSObject (FSKVCoding)
- (id)fskvWrapper; // if this returns something other than nil, use this.
// extension of NSClassDescription methods (may be overridden)
- (NSArray *)fskvUnclassifiedRelationshipKeys;
- (id)fskvValueForKey:(NSString *)key;
- (void)fskvTakeValue:(id)value forKey:(NSString *)key;

    // information regarding the accessability of properties. (may be overridden)
- (BOOL)fskvIsValidKey:(NSString *)key;
- (BOOL)fskvAllowsToGetValueForKey:(NSString *)key; // might disallow read access
- (BOOL)fskvAllowsToTakeValueForKey:(NSString *)key; // might disallow setting for all values
- (BOOL)fskvAllowsToTakeValue:(id)value forKey:(NSString *)key; // might disallow setting of special values

    // convenience methods to get all Keys (not to be overridden)
- (NSMutableArray *)fskvKeysWithFilterBits:(int)filter; // -1 for all
- (NSMutableArray *)fskvKeysWithFilterArray:(NSArray *)filter;
@end

@interface NSArray (FSKVCoding)
// extension of NSClassDescription methods (may be overridden)
- (NSArray *)fskvUnclassifiedRelationshipKeys;
- (id)fskvValueForKey:(NSString *)key;

    // information regarding the accessability of properties. (may be overridden)
- (BOOL)fskvIsValidKey:(NSString *)key;
- (BOOL)fskvAllowsToTakeValueForKey:(NSString *)key; // might disallow setting for all values
@end

@interface NSMutableArray (FSKVCoding)
// extension of NSClassDescription methods (may be overridden)
- (void)fskvTakeValue:(id)value forKey:(NSString *)key;
- (BOOL)fskvAllowsToTakeValueForKey:(NSString *)key; // might disallow setting for all values
- (BOOL)fskvAllowsToTakeValue:(id)value forKey:(NSString *)key; // disallow nil values
@end

@interface NSDictionary (FSKVCoding)
// extension of NSClassDescription methods (may be overridden)
- (NSArray *)fskvUnclassifiedRelationshipKeys;
- (id)fskvValueForKey:(NSString *)key;

    // information regarding the accessability of properties. (may be overridden)
- (BOOL)fskvIsValidKey:(NSString *)key;
- (BOOL)fskvAllowsToTakeValueForKey:(NSString *)key; // might disallow setting for all values
@end

@interface NSMutableDictionary (FSKVCoding)
// extension of NSClassDescription methods (may be overridden)
- (void)fskvTakeValue:(id)value forKey:(NSString *)key;
- (BOOL)fskvAllowsToTakeValueForKey:(NSString *)key; // might disallow setting for all values
- (BOOL)fskvAllowsToTakeValue:(id)value forKey:(NSString *)key; // disallow nil values
@end

// dont know how to handle Sets! The elements are not accessable by key.
// but maybe we can create a wrapper, which transforms fskv- and standard kv Methods to
// the delegate.
//- (id)fskvWrapper; // if this returns something other than nil, use this.
