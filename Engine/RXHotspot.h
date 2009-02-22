//
//	RXHotspot.h
//	rivenx
//
//	Created by Jean-Francois Roy on 31/05/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface RXHotspot : NSObject {
	uint16_t _index;
	uint16_t _ID;
	NSRect _cardFrame;
	uint16_t _cursorID;
	NSDictionary* _script;
	
	NSString* _description;
	NSRect _globalFrame;

@public
	BOOL enabled;
}

- (id)initWithIndex:(uint16_t)index ID:(uint16_t)ID frame:(NSRect)frame cursorID:(uint16_t)cursorID script:(NSDictionary*)script;

- (void)setName:(NSString*)name;

- (NSRect)worldViewFrame;
- (uint16_t)cursorID;
- (NSDictionary*)script;

- (void)enable;

@end
