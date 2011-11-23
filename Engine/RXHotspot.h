//
//  RXHotspot.h
//  rivenx
//
//  Created by Jean-Francois Roy on 31/05/2006.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"

#import "Engine/RXCoreStructures.h"
#import "Rendering/RXRendering.h"


@interface RXHotspot : NSObject {
    uint16_t _index;
    uint16_t _ID;
    rx_core_rect_t _rect;
    uint16_t _cursor_id;
    NSDictionary* _script;
    
    NSString* _name;
    NSString* _description;
    NSRect _world_frame;
    
    rx_event_t _event;

@public
    BOOL enabled;
}

- (id)initWithIndex:(uint16_t)index ID:(uint16_t)ID rect:(rx_core_rect_t)rect cursorID:(uint16_t)cursorID script:(NSDictionary*)script;

- (NSString*)name;
- (void)setName:(NSString*)name;

- (uint16_t)ID;
- (uint16_t)cursorID;
- (NSDictionary*)scripts;

- (rx_core_rect_t)coreFrame;
- (void)setCoreFrame:(rx_core_rect_t)frame;

- (NSRect)worldFrame;

- (rx_event_t)event;
- (void)setEvent:(rx_event_t)event;

- (void)enable;

@end
