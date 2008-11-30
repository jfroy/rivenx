//
//	RXHotspot.h
//	rivenx
//
//	Created by Jean-Francois Roy on 31/05/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//


@interface RXHotspot : NSObject {
@private
	uint16_t _index;
	uint16_t _ID;
	NSString* _name;
	NSRect _cardFrame;
	uint16_t _cursorID;
	NSDictionary* _script;
	
	NSRect _globalFrame;
@public
	// ONLY FOR RXCard
	BOOL enabled;
}

- (id)initWithIndex:(uint16_t)index ID:(uint16_t)ID frame:(NSRect)frame cursorID:(uint16_t)cursorID script:(NSDictionary*)script;

- (NSRect)worldViewFrame;
- (uint16_t)cursorID;
- (NSDictionary*)script;

- (void)enable;

@end
