//
//	RXGameState.h
//	rivenx
//
//	Created by Jean-Francois Roy on 02/11/2007.
//	Copyright 2007 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RXEdition.h"
#import "RXCardDescriptor.h"


@interface RXGameState : NSObject <NSCoding> {
	RXEdition* _edition;
	NSMutableDictionary* _variables;
	RXSimpleCardDescriptor* _currentCard;
	RXSimpleCardDescriptor* _returnCard;
	NSURL* _URL;
	NSRecursiveLock* _accessLock;
}

+ (RXGameState*)gameStateWithURL:(NSURL*)url error:(NSError**)error;

- (id)initWithEdition:(RXEdition*)edition;

- (void)dump;

- (NSURL*)URL;
- (BOOL)writeToURL:(NSURL*)url error:(NSError**)error;

- (uint16_t)unsignedShortForKey:(NSString*)key;
- (int16_t)shortForKey:(NSString*)key;

- (void)setUnsignedShort:(uint16_t)value forKey:(NSString*)key;
- (void)setShort:(int16_t)value forKey:(NSString*)key;

- (BOOL)isKeySet:(NSString*)key;

- (RXSimpleCardDescriptor*)currentCard;
- (void)setCurrentCard:(RXSimpleCardDescriptor*)descriptor;

- (RXSimpleCardDescriptor*)returnCard;
- (void)setReturnCard:(RXSimpleCardDescriptor*)descriptor;

@end
