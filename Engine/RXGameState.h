//
//  RXGameState.h
//  rivenx
//
//  Created by Jean-Francois Roy on 02/11/2007.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"

@class NSRecursiveLock;
@class RXSimpleCardDescriptor;

@interface RXGameState : NSObject <NSCoding> {
  NSMutableDictionary* _variables;
  RXSimpleCardDescriptor* _currentCard;
  RXSimpleCardDescriptor* _returnCard;
  NSURL* _URL;
  NSRecursiveLock* _accessLock;
}

+ (RXGameState*)gameStateWithURL:(NSURL*)url error:(NSError**)error;

- (id)init;

- (void)dump;

- (NSURL*)URL;
- (BOOL)writeToURL:(NSURL*)url error:(NSError**)error;
- (BOOL)writeToURL:(NSURL*)url updateURL:(BOOL)update error:(NSError**)error;

- (uint16_t)unsignedShortForKey:(NSString*)key;
- (void)setUnsignedShort:(uint16_t)value forKey:(NSString*)key;
- (int16_t)shortForKey:(NSString*)key;
- (void)setShort:(int16_t)value forKey:(NSString*)key;

- (uint32_t)unsigned32ForKey:(NSString*)key;
- (void)setUnsigned32:(uint32_t)value forKey:(NSString*)key;
- (int32_t)signed32ForKey:(NSString*)key;
- (void)setSigned32:(int32_t)value forKey:(NSString*)key;

- (uint64_t)unsigned64ForKey:(NSString*)key;
- (void)setUnsigned64:(uint64_t)value forKey:(NSString*)key;
- (int64_t)signed64ForKey:(NSString*)key;
- (void)setSigned64:(int64_t)value forKey:(NSString*)key;

- (BOOL)isKeySet:(NSString*)key;

- (RXSimpleCardDescriptor*)currentCard;
- (void)setCurrentCard:(RXSimpleCardDescriptor*)descriptor;

- (RXSimpleCardDescriptor*)returnCard;
- (void)setReturnCard:(RXSimpleCardDescriptor*)descriptor;

@end
