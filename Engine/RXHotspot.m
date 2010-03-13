//
//  RXHotspot.m
//  rivenx
//
//  Created by Jean-Francois Roy on 31/05/2006.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "Engine/RXHotspot.h"
#import "Engine/RXScriptCommandAliases.h"
#import "Engine/RXScriptDecoding.h"
#import "Rendering/RXRendering.h"


@implementation RXHotspot

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (void)_updateWorldFrame:(NSNotification*)notification {
    _world_frame = RXTransformRectCoreToWorld(_rect);
}

- (void)_scanMouseInsidePrograms {
    NSArray* programs = [_script objectForKey:RXMouseInsideScriptKey];
    assert(programs);
    
    uint32_t p_count = [programs count];
    if (p_count == 0 || p_count > 1)
        return;
    
    NSDictionary* program_dict = [programs objectAtIndex:0];
    uint16_t i_count = [[program_dict objectForKey:RXScriptOpcodeCountKey] unsignedShortValue];
    if (i_count == 0 || i_count > 1)
        return;
    
    const uint16_t* program = (uint16_t*)[[program_dict objectForKey:RXScriptProgramKey] bytes];
    if (program[0] != RX_COMMAND_SET_CURSOR)
        return;
    if (program[1] != 1)
        return;
    
    // our "mouse inside" script consist of a single "set cursor" command, so we'll just override our cursor
    _cursor_id = program[2];
    
    // and scrap our mouse inside program
    NSMutableDictionary* mut_script = [_script mutableCopy];
    [mut_script setObject:[NSArray array] forKey:RXMouseInsideScriptKey];
    [_script release];
    _script = mut_script;
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
    
    // register for reshape notifications so we can update our world frame and do an update immediately to initialize the world frame
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateWorldFrame:) name:@"RXOpenGLDidReshapeNotification" object:nil];
    [self _updateWorldFrame:nil];
    
    // scan if we have a "mouse inside" script, and is so whether that script only sets a cursor
    [self _scanMouseInsidePrograms];
    
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

- (void)_updateDescription {
    [_description release];
    
    if (_name)
        _description = [[NSString alloc] initWithFormat: @"%@ {ID=%hu, core=<%hu, %hu, %hu, %hu>, world=<%d, %d, %d, %d>}",
            _name, _ID,
            _rect.left, _rect.top, _rect.right, _rect.bottom,
            (int)_world_frame.origin.x, (int)_world_frame.origin.y, (int)_world_frame.size.width, (int)_world_frame.size.height];
    else
        _description = [[NSString alloc] initWithFormat: @"{ID=%hu, core=<%hu, %hu, %hu, %hu>, world=<%d, %d, %d, %d>}",
            _ID,
            _rect.left, _rect.top, _rect.right, _rect.bottom,
            (int)_world_frame.origin.x, (int)_world_frame.origin.y, (int)_world_frame.size.width, (int)_world_frame.size.height];
}

- (NSString*)description {
    if (!_description)
        [self _updateDescription];
    return [[_description retain] autorelease];
}

- (NSString*)name {
    return [[_name retain] autorelease];
}

- (void)setName:(NSString*)name {
    if (_name == name)
        return;
    
    [_name release];
    _name = [name copy];
    
    [self _updateDescription];
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
    [self _updateDescription];
}

- (uint16_t)cursorID {
    return _cursor_id;
}

- (NSDictionary*)scripts {
    return _script;
}

- (NSRect)worldFrame {
    return _world_frame;
}

- (rx_event_t)event {
    return _event;
}

- (void)setEvent:(rx_event_t)event {
    _event = event;
}

- (void)enable {
    enabled = YES;
}

@end
