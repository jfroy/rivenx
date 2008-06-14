//
//	RXGameState.h
//	rivenx
//
//	Created by Jean-Francois Roy on 02/11/2007.
//	Copyright 2007 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RXCardDescriptor.h"


@interface RXGameState : NSObject <NSCoding> {
	NSMutableDictionary* _variables;
	RXSimpleCardDescriptor* _currentCard;
}

- (void)dump;

- (uint16_t)unsignedShortForKey:(NSString*)key;
- (int16_t)shortForKey:(NSString*)key;

- (void)setUnsignedShort:(uint16_t)value forKey:(NSString*)key;
- (void)setShort:(int16_t)value forKey:(NSString*)key;

- (BOOL)isKeySet:(NSString*)key;

- (RXSimpleCardDescriptor*)currentCard;
- (void)setCurrentCard:(RXSimpleCardDescriptor*)descriptor;

@end
