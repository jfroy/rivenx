//
//	RXGameState.h
//	rivenx
//
//	Created by Jean-Francois Roy on 02/11/2007.
//	Copyright 2007 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface RXGameState : NSObject {
	NSMutableDictionary* _variables;
	BOOL _dvdEdition;
}

- (void)dump;

- (BOOL)dvdEdition;
- (void)setDVDEdition:(BOOL)f;

- (uint16_t)unsignedShortForKey:(NSString*)key;
- (int16_t)shortForKey:(NSString*)key;

- (void)setUnsignedShort:(uint16_t)value forKey:(NSString*)key;
- (void)setShort:(int16_t)value forKey:(NSString*)key;

- (BOOL)isKeySet:(NSString*)key;

@end
