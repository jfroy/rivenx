//
//  RXHotspot.m
//  rivenx
//
//  Created by Jean-Francois Roy on 31/05/2006.
//  Copyright 2006 MacStorm. All rights reserved.
//

#import "RXHotspot.h"

#import "Rendering/RXRendering.h"


@implementation RXHotspot

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (void)_updateWorldFrame:(NSNotification*)notification {
    rx_rect_t render_frame = RXEffectiveRendererFrame();
    float scale_x = (float)render_frame.size.width / (float)kRXRendererViewportSize.width;
    float scale_y = (float)render_frame.size.height / (float)kRXRendererViewportSize.height;
    
    NSRect composite_rect = RXMakeCompositeDisplayRectFromCoreRect(_rect);
    
    _world_frame.origin.x = render_frame.origin.x + (composite_rect.origin.x + kRXCardViewportOriginOffset.x) * scale_x;
    _world_frame.origin.y = render_frame.origin.y + (composite_rect.origin.y + kRXCardViewportOriginOffset.y) * scale_y;
    _world_frame.size.width = composite_rect.size.width * scale_x;
    _world_frame.size.height = composite_rect.size.height * scale_y;
}

- (id)initWithIndex:(uint16_t)index ID:(uint16_t)ID rect:(rx_core_rect_t)rect cursorID:(uint16_t)cursorID script:(NSDictionary*)script {
    self = [super init];
    if (!self)
        return nil;
    
    _index = index;
    _ID = ID;
    _rect = rect;
    _cursor_id = cursorID;
    _script = [script retain];
    
    _description = [[NSString alloc] initWithFormat: @"{ID=%hu, rect=<%hu, %hu, %hu, %hu>}", _ID, _rect.left, _rect.top, _rect.right, _rect.bottom];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateWorldFrame:) name:@"RXOpenGLDidReshapeNotification" object:nil];
    [self _updateWorldFrame:nil];
    
#if defined(DEBUG) && DEBUG > 1
    NSMutableString* hotspot_handlers = [NSMutableString new];
    NSArray* keys = [[_script allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSEnumerator* handlers = [keys objectEnumerator];
    NSString* key;
    while((key = [handlers nextObject]))
        [hotspot_handlers appendFormat:@"     %@ = %d\n", key, [[_script objectForKey:key] count]];
    RXOLog(@"hotspot script:\n%@", hotspot_handlers);
    [hotspot_handlers release];
#endif
    
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_name release];
    [_description release];
    [_script release];
    
    [super dealloc];
}

- (NSComparisonResult)compareByIndex:(RXHotspot*)other {
    if (other->_index < _index)
        return NSOrderedAscending;
    else
        return NSOrderedDescending;
}

- (NSComparisonResult)compareByID:(RXHotspot*)other {
    if (other->_ID < _ID)
        return NSOrderedAscending;
    else
        return NSOrderedDescending;
}

- (NSString*)description {
    return _description;
}

- (NSString*)name {
    return [[_name retain] autorelease];
}

- (void)setName:(NSString*)name {
    if (_name == name)
        return;
    
    [_description release];
    _description = [[NSString alloc] initWithFormat: @"%@ {ID=%hu, rect=<%hu, %hu, %hu, %hu>}", name, _ID, _rect.left, _rect.top, _rect.right, _rect.bottom];
    
    [_name release];
    _name = [name retain];
}

- (uint16_t)ID {
    return _ID;
}

- (rx_core_rect_t)coreFrame {
    return _rect;
}

- (void)setCoreFrame:(rx_core_rect_t)frame {
    _rect = frame;
    [self _updateWorldFrame:nil];
}

- (uint16_t)cursorID {
    return _cursor_id;
}

- (NSDictionary*)script {
    return _script;
}

- (NSRect)worldFrame {
    return _world_frame;
}

- (void)enable {
    enabled = YES;
}

@end
