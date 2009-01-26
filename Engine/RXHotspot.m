//
//	RXHotspot.m
//	rivenx
//
//	Created by Jean-Francois Roy on 31/05/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import "RXHotspot.h"

#import "Rendering/RXRendering.h"


@implementation RXHotspot

- (id)init {
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (void)_updateGlobalFrame:(NSNotification*)notification {
	rx_rect_t contentRect = RXEffectiveRendererFrame();
	float scale_x = (float)contentRect.size.width / (float)kRXRendererViewportSize.width;
	float scale_y = (float)contentRect.size.height / (float)kRXRendererViewportSize.height;
	
	_globalFrame.origin.x = contentRect.origin.x + (_cardFrame.origin.x + kRXCardViewportOriginOffset.x) * scale_x;
	_globalFrame.origin.y = contentRect.origin.y + (_cardFrame.origin.y + kRXCardViewportOriginOffset.y) * scale_y;
	_globalFrame.size.width = _cardFrame.size.width * scale_x;
	_globalFrame.size.height = _cardFrame.size.height * scale_y;
}

- (id)initWithIndex:(uint16_t)index ID:(uint16_t)ID frame:(NSRect)frame cursorID:(uint16_t)cursorID script:(NSDictionary*)script {
	self = [super init];
	if (!self) return nil;
	
	_index = index;
	_ID = ID;
	_name = nil;
	_cardFrame = frame;
	_cursorID = cursorID;
	_script = [script retain];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateGlobalFrame:) name:@"RXOpenGLDidReshapeNotification" object:nil];
	[self _updateGlobalFrame:nil];
	
#if defined(DEBUG) && DEBUG > 1
	NSMutableString* hotspot_handlers = [NSMutableString new];
	NSArray* keys = [[_script allKeys] sortedArrayUsingSelector:@selector(compare:)];
	NSEnumerator* handlers = [keys objectEnumerator];
	NSString* key;
	while((key = [handlers nextObject]))
		[hotspot_handlers appendFormat:@"	  %@ = %d\n", key, [[_script objectForKey:key] count]];
	RXOLog(@"hotspot script:\n%@", hotspot_handlers);
	[hotspot_handlers release];
#endif
	
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[_name release];
	[_script release];
	
	[super dealloc];
}

- (NSComparisonResult)compareByIndex:(RXHotspot*)other {
	if (other->_index < _index)
		return NSOrderedAscending;
	else
		return NSOrderedDescending;
}

- (NSRect)worldViewFrame {
	return _globalFrame;
}

- (uint16_t)cursorID {
	return _cursorID;
}

- (NSDictionary*)script {
	return _script;
}

- (NSString*)description {
	return [NSString stringWithFormat: @"%@ {ID=%hu, frame=%@}", [super description], _ID, NSStringFromRect(_cardFrame)];
}

- (void)enable {
	enabled = YES;
}

@end
