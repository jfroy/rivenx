//
//  RXCard.m
//  rivenx
//
//  Created by Jean-Francois Roy on 30/08/2005.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import <mach/task.h>
#import <mach/thread_act.h>
#import <mach/thread_policy.h>

#import "Engine/RXCard.h"

#import "Engine/RXCursors.h"
#import "Engine/RXScriptDecoding.h"
#import "Engine/RXScriptCommandAliases.h"
#import "Engine/RXScriptCompiler.h"

#import "Rendering/Graphics/RXMovieProxy.h"


@implementation RXCard

+ (BOOL)accessInstanceVariablesDirectly {
    return NO;
}

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithCardDescriptor:(RXCardDescriptor*)cardDescriptor {
    self = [super init];
    if (!self)
        return nil;
    
    // check that the descriptor is "valid"
    if (!cardDescriptor || ![cardDescriptor isKindOfClass:[RXCardDescriptor class]]) { 
        [self release];
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Card descriptor object is nil or of the wrong type."
                                     userInfo:nil];
    }
    
    // NOTE: Stack descriptors belong to cards initialized with them, and to the object that initialized the descriptor.
    //       Consequently, if the object that initialized the descriptor owns the corresponding card, it can release the descriptor.
    
    // keep the descriptor around
    _descriptor = [cardDescriptor retain];
    
    // retain our parent stack, since RXCardDescriptor only keeps a weak reference to it
    _parent = [[cardDescriptor parent] retain];
    
//    NSData* card_data = [_descriptor data];
//    
//    uint16_t zipCard = CFSwapInt16BigToHost(*(const uint16_t *)([card_data bytes] + 2));
//    NSNumber* zipCardNumber = [NSNumber numberWithBool:(zipCard) ? YES : NO];
    
    return self;
}

- (void)dealloc {
#if defined(DEBUG) && DEBUG > 1
    RXOLog(@"deallocating");
#endif

    // stop receiving notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // movies
    [_movies release];
    if (_mlstCodes)
        free(_mlstCodes);
    
    // pictures
    if (_plst_data)
        free(_plst_data);
    
    // sounds
    [_soundGroups release];
    
    // hotspots
    if (_hotspotsIDMap)
        NSFreeMapTable(_hotspotsIDMap);
    if (_hotspots_name_map)
        NSFreeMapTable(_hotspots_name_map);
    [_hotspots release];
    
    // sfxe
    if (_sfxes) {
        for (uint16_t i = 0; i < _flstCount; i++) {
            free(_sfxes[i].record);
        }
        free(_sfxes);
    }
    
    // misc resources
    if (_blstData)
        free(_blstData);
    [_card_scripts release];
    
    [_parent release];
    [_descriptor release];
    
    [super dealloc];
}

- (NSString*)name {
    return [_descriptor name];
}

- (NSString*)description {
    return [NSString stringWithFormat: @"%@ {%@}", [super description], [_descriptor description]];
}

#pragma mark -
#pragma mark loading

- (void)_loadScripts {
    NSData* card_data = [_descriptor data];
    
    // card events
    _card_scripts = rx_decode_riven_script(BUFFER_OFFSET([card_data bytes], 4), NULL);
    
    // get the current edition
//    RXEdition* ce = [[RXEditionManager sharedEditionManager] currentEdition];
    
    // WORKAROUND: there is a legitimate bug in the CD edition's tspit 155 open card program;
    // FIXME: need a new "is CD edition" check
    // it executes activate SLST record 2 command after the introduction sequence, which is the mute SLST; patch it up to activate SLST 1
//    if ([_descriptor isCardWithRMAP:28314 stackName:@"tspit"] && [[ce valueForKey:@"key"] isEqualToString:@"CD_EDITION"]) {
    if ([_descriptor isCardWithRMAP:28314 stackName:@"tspit"]) {
        NSDictionary* start_rendering_program = [[_card_scripts objectForKey:RXStartRenderingScriptKey] objectAtIndex:0];
        RXScriptCompiler* comp = [[RXScriptCompiler alloc] initWithCompiledScript:start_rendering_program];
        NSMutableArray* dp = [comp decompiledScript];
        
        NSDictionary* opcode = [dp objectAtIndex:0];
        if (RX_OPCODE_COMMAND_EQ(opcode, RX_COMMAND_BRANCH)) {
            NSDictionary* case0 = [[opcode objectForKey:@"cases"] objectAtIndex:0];
            if (RX_CASE_VAL_EQ(case0, 0)) {
                opcode = [[case0 objectForKey:@"block"] objectAtIndex:26];
                if (RX_OPCODE_COMMAND_EQ(opcode, RX_COMMAND_ACTIVATE_SLST) && RX_OPCODE_ARG(opcode, 0) == 2)
                    RX_OPCODE_SET_ARG(opcode, 0, 1);
            }
        }
        
        [comp setDecompiledScript:dp];
        
        NSMutableDictionary* mutable_script = [_card_scripts mutableCopy];
        [mutable_script setObject:[NSArray arrayWithObject:[comp compiledScript]] forKey:RXStartRenderingScriptKey];
        
        [_card_scripts release];
        _card_scripts = mutable_script;
        
        [comp release];
    }
    // WORKAROUND: patch pspit 29's start rendering script to remove the instruction that sets atrapbook to 0
    else if ([_descriptor isCardWithRMAP:2526 stackName:@"pspit"]) {
        NSDictionary* start_rendering_program = [[_card_scripts objectForKey:RXStartRenderingScriptKey] objectAtIndex:0];
        RXScriptCompiler* comp = [[RXScriptCompiler alloc] initWithCompiledScript:start_rendering_program];
        NSMutableArray* dp = [comp decompiledScript];
        
        NSDictionary* opcode = [dp lastObject];
        if (RX_OPCODE_COMMAND_EQ(opcode, RX_COMMAND_BRANCH)) {
            NSDictionary* case0 = [[opcode objectForKey:@"cases"] objectAtIndex:0];
            if (RX_BRANCH_VAR_NAME_EQ(opcode, @"pcage") && RX_CASE_VAL_EQ(case0, 1)) {
                NSMutableArray* block = [case0 objectForKey:@"block"];
                uint32_t n = [block count];
                for (uint32_t i = 0; i < n; i++) {
                    opcode = [block objectAtIndex:i];
                    if (RX_OPCODE_COMMAND_EQ(opcode, RX_COMMAND_SET_VARIABLE) && RX_VAR_NAME_EQ(RX_OPCODE_ARG(opcode, 0), @"atrapbook")) {
                        [block removeObjectAtIndex:i];
                        n--;
                        i--;
                    } else if (RX_OPCODE_COMMAND_EQ(opcode, RX_COMMAND_START_MOVIE_BLOCKING) && RX_OPCODE_ARG(opcode, 0) == 3) {
                        uint32_t movie_time = 41000; // ms
                        opcode = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSNumber numberWithUnsignedShort:RX_COMMAND_SCHEDULE_MOVIE_COMMAND], @"command",
                            [NSArray arrayWithObjects:
                                [NSNumber numberWithUnsignedShort:3], // movie code
                                [NSNumber numberWithUnsignedShort:movie_time >> 16], // movie time
                                [NSNumber numberWithUnsignedShort:movie_time & 0xFFFF],
                                [NSNumber numberWithUnsignedShort:RX_COMMAND_SET_VARIABLE], // scheduled command
                                [NSNumber numberWithUnsignedShort:[_parent varIndexForName:@"atrapbook"]], // scheduled command args
                                [NSNumber numberWithUnsignedShort:0],
                                nil], @"args",
                            nil];
                        [block insertObject:opcode atIndex:i];
                        i++;
                        n++;
                    }
                }
            }
        }
        
        [comp setDecompiledScript:dp];
        
        NSMutableDictionary* mutable_script = [_card_scripts mutableCopy];
        [mutable_script setObject:[NSArray arrayWithObject:[comp compiledScript]] forKey:RXStartRenderingScriptKey];
        
        [_card_scripts release];
        _card_scripts = mutable_script;
        
        [comp release];
    }
}

- (void)_loadPictures {
    NSError* error;
    MHKFileHandle* fh;
    size_t list_data_size;
    uint16_t list_index;
    
    fh = [_parent fileWithResourceType:@"PLST" ID:[_descriptor ID]];
    if (!fh)
        @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                       reason:@"Could not open the card's corresponding PLST resource."
                                     userInfo:nil];
    
    list_data_size = (size_t)[fh length];
    _plst_data = malloc(list_data_size);
    
    // read the data from the archive
    if ([fh readDataToEndOfFileInBuffer:_plst_data error:&error] == -1)
        @throw [NSException exceptionWithName:@"RXRessourceIOException"
                                       reason:@"Could not read the card's corresponding PLST ressource."
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    
    // how many pictures do we have?
    _picture_count = CFSwapInt16BigToHost(*(uint16_t*)_plst_data);
    struct rx_plst_record* picture_records = (struct rx_plst_record*)BUFFER_OFFSET(_plst_data, sizeof(uint16_t));
    
    // process the picture records
    for (list_index = 0; list_index < _picture_count; list_index++) {
        struct rx_plst_record* picture_record = picture_records + list_index;
        
#if defined(__LITTLE_ENDIAN__)
        picture_record->index = CFSwapInt16(picture_record->index);
        picture_record->bitmap_id = CFSwapInt16(picture_record->bitmap_id);
        picture_record->rect = rx_swap_core_rect(picture_record->rect);
#endif
        
        MHKArchive* archive = [[_parent fileWithResourceType:@"tBMP" ID:picture_record->bitmap_id] archive];
        NSDictionary* picture_descriptor = [archive bitmapDescriptorWithID:picture_record->bitmap_id error:&error];
        if (!picture_descriptor)
            @throw [NSException exceptionWithName:@"RXPictureLoadException"
                                           reason:@"Could not get a picture resource's picture descriptor."
                                         userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
        
        GLsizei width = [[picture_descriptor objectForKey:@"Width"] intValue];
        GLsizei height = [[picture_descriptor objectForKey:@"Height"] intValue];
        
#if defined(DEBUG) && DEBUG > 1
        NSRect original_rect = RXMakeCompositeDisplayRectFromCoreRect(picture_record->rect);
        if (width != original_rect.size.width || height != original_rect.size.height)
            RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug,
                @"PLST record %hu has display rect size different than tBMP resource %hu: %dx%d vs. %dx%d",
                picture_record->index,
                picture_record->bitmap_id,
                original_rect.size.width,
                original_rect.size.height,
                picture_record->rect.right - picture_record->rect.left,
                picture_record->rect.bottom - picture_record->rect.top);
#endif
        
        // adjust the display rect to anchor the picture to the top-left corner
        // while clipping the picture to its size (and never scaling the
        // picture either)
        if (picture_record->rect.right - picture_record->rect.left > width)
            picture_record->rect.right = picture_record->rect.left + width;
        if (picture_record->rect.bottom - picture_record->rect.top > height)
            picture_record->rect.bottom = picture_record->rect.top + height;
    }
}

- (void)_loadMovies {
    NSError* error;
    MHKFileHandle* fh;
    void* list_data;
    size_t list_data_size;
    uint16_t list_index;
    
    fh = [_parent fileWithResourceType:@"MLST" ID:[_descriptor ID]];
    if (!fh)
        @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                       reason:@"Could not open the card's corresponding MLST resource."
                                     userInfo:nil];
    
    list_data_size = (size_t)[fh length];
    list_data = malloc(list_data_size);
    
    // read the data from the archive
    if ([fh readDataToEndOfFileInBuffer:list_data error:&error] == -1)
        @throw [NSException exceptionWithName:@"RXRessourceIOException"
                                       reason:@"Could not read the card's corresponding MLST ressource."
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    
    // how many movies do we have?
    uint16_t movieCount = CFSwapInt16BigToHost(*(uint16_t*)list_data);
    struct rx_mlst_record* mlstRecords = (struct rx_mlst_record*)BUFFER_OFFSET(list_data, sizeof(uint16_t));
    
    // allocate movie management objects
    _movies = [NSMutableArray new];
    _mlstCodes = malloc(sizeof(uint16_t) * movieCount);
    
    BOOL fixup_rebel_end_loop = [[_descriptor parent] cardRMAPCodeFromID:[_descriptor ID]] == 13112 &&
                                [[[_descriptor parent] key] isEqualToString:@"rspit"];
    
    // swap the records if needed
#if defined(__LITTLE_ENDIAN__)
    for (list_index = 0; list_index < movieCount; list_index++) {
        mlstRecords[list_index].index = CFSwapInt16(mlstRecords[list_index].index);
        mlstRecords[list_index].movie_id = CFSwapInt16(mlstRecords[list_index].movie_id);
        mlstRecords[list_index].code = CFSwapInt16(mlstRecords[list_index].code);
        mlstRecords[list_index].left = CFSwapInt16(mlstRecords[list_index].left);
        mlstRecords[list_index].top = CFSwapInt16(mlstRecords[list_index].top);
        mlstRecords[list_index].selection_start = CFSwapInt16(mlstRecords[list_index].selection_start);
        mlstRecords[list_index].selection_current = CFSwapInt16(mlstRecords[list_index].selection_current);
        mlstRecords[list_index].selection_end = CFSwapInt16(mlstRecords[list_index].selection_end);
        mlstRecords[list_index].loop = CFSwapInt16(mlstRecords[list_index].loop);
        mlstRecords[list_index].volume = CFSwapInt16(mlstRecords[list_index].volume);
        mlstRecords[list_index].rate = CFSwapInt16(mlstRecords[list_index].rate);
    }
#endif
    
    for (list_index = 0; list_index < movieCount; list_index++) {
#if defined(DEBUG) && DEBUG > 1
        RXOLog(@"loading mlst entry: {movie ID: %hu, code: %hu, left: %hu, top: %hu, loop: %hu, volume: %hu}",
            mlstRecords[list_index].movie_id,
            mlstRecords[list_index].code,
            mlstRecords[list_index].left,
            mlstRecords[list_index].top,
            mlstRecords[list_index].loop,
            mlstRecords[list_index].volume);
#endif
        
        // sometimes volume > 255, so fix it up here
        if (mlstRecords[list_index].volume > 255)
            mlstRecords[list_index].volume = 255;
        
        // WORKAROUND: for some obscure reason, the endgame movies from the
        // rebel age are set to loop and it screws up a lot of things...
        if (fixup_rebel_end_loop)
            mlstRecords[list_index].loop = 0;
        
        // load the movie up
        CGPoint origin = CGPointMake(mlstRecords[list_index].left, kRXCardViewportSize.height - mlstRecords[list_index].top);
        MHKArchive* archive = [[_parent fileWithResourceType:@"tMOV" ID:mlstRecords[list_index].movie_id] archive];
        RXMovieProxy* movie_proxy = [[RXMovieProxy alloc] initWithArchive:archive
                                                                       ID:mlstRecords[list_index].movie_id
                                                                   origin:origin
                                                                   volume:mlstRecords[list_index].volume / 255.0f
                                                                     loop:((mlstRecords[list_index].loop == 1) ? YES : NO)
                                                                    owner:self];
        
        // add the movie to the movies array
        [_movies addObject:movie_proxy];
        [movie_proxy release];
        
        // set the movie code in the mlst to code array
        _mlstCodes[list_index] = mlstRecords[list_index].code;
    }
    
    // don't need the MLST data anymore
    free(list_data);
}

- (void)_loadHotspots {
    NSError* error;
    MHKFileHandle* fh;
    void* list_data;
    size_t list_data_size;
    uint16_t list_index;
    
    fh = [_parent fileWithResourceType:@"HSPT" ID:[_descriptor ID]];
    if (!fh)
        @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                       reason:@"Could not open the card's corresponding HSPT resource."
                                     userInfo:nil];
    
    list_data_size = (size_t)[fh length];
    list_data = malloc(list_data_size);
    
    // read the data from the archive
    if ([fh readDataToEndOfFileInBuffer:list_data error:&error] == -1)
        @throw [NSException exceptionWithName:@"RXRessourceIOException"
                                       reason:@"Could not read the card's corresponding HSPT ressource."
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    
    // how many hotspots do we have?
    uint16_t hotspotCount = CFSwapInt16BigToHost(*(uint16_t*)list_data);
    uint8_t* hsptRecordPointer = (uint8_t*)BUFFER_OFFSET(list_data, sizeof(uint16_t));
    if (_hotspots)
        [_hotspots release];
    _hotspots = [[NSMutableArray alloc] initWithCapacity:hotspotCount];
    
    if (_hotspotsIDMap)
        NSFreeMapTable(_hotspotsIDMap);
    _hotspotsIDMap = NSCreateMapTable(NSIntegerMapKeyCallBacks, NSNonRetainedObjectMapValueCallBacks, hotspotCount);
    if (_hotspots_name_map)
        NSFreeMapTable(_hotspots_name_map);
    _hotspots_name_map = NSCreateMapTable(NSObjectMapKeyCallBacks, NSNonRetainedObjectMapValueCallBacks, hotspotCount);
    
    // load the hotspots
    for (list_index = 0; list_index < hotspotCount; list_index++) {
        struct rx_hspt_record* hspt_record = (struct rx_hspt_record*)hsptRecordPointer;
        hsptRecordPointer += sizeof(struct rx_hspt_record);
        
        // byte order swap if needed
#if defined(__LITTLE_ENDIAN__)
        hspt_record->blst_id = CFSwapInt16(hspt_record->blst_id);
        hspt_record->name_rec = (int16_t)CFSwapInt16(hspt_record->name_rec);
        hspt_record->rect = rx_swap_core_rect(hspt_record->rect);
        hspt_record->u0 = CFSwapInt16(hspt_record->u0);
        hspt_record->mouse_cursor = CFSwapInt16(hspt_record->mouse_cursor);
        hspt_record->index = CFSwapInt16(hspt_record->index);
        hspt_record->u1 = (int16_t)CFSwapInt16(hspt_record->u1);
        hspt_record->zip = CFSwapInt16(hspt_record->zip);
#endif

#if defined(DEBUG) && DEBUG > 1
        RXOLog(@"hotspot record %u: index=%hd, blst_id=%hd, zip=%hu", list_index, hspt_record->index, hspt_record->blst_id, hspt_record->zip);
#endif
        
        // decode the hotspot's script
        uint32_t script_size = 0;
        NSDictionary* hotspot_scripts = rx_decode_riven_script(hsptRecordPointer, &script_size);
        hsptRecordPointer += script_size;
        
        // if this is a zip hotspot, skip it if Zip mode is disabled
        // FIXME: Zip mode is always disabled currently
        if (hspt_record->zip == 1)
            continue;
        
        // get the hotspot's name (if it has one)
        NSString* hotspotName = nil;
        if (hspt_record->name_rec >= 0)
            hotspotName = [[[_descriptor parent] hotspotNameAtIndex:hspt_record->name_rec] lowercaseString];
        
        // WORKAROUND: there is a legitimate bug in aspit's "start new game" hotspot; it executes a command 12 at the very end,
        // which kills ambient sound after the introduction sequence; we remove that command here
        if ([_descriptor ID] == 1 && [[[_descriptor parent] key] isEqualToString:@"aspit"] && hspt_record->blst_id == 16) {
            NSDictionary* program = [[hotspot_scripts objectForKey:RXMouseDownScriptKey] objectAtIndex:0];
            
            uint16_t opcode_count = [[program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue];
            if (opcode_count > 0 && rx_get_riven_script_opcode([[program objectForKey:RXScriptProgramKey] bytes],
                                                               opcode_count,
                                                               opcode_count - 1,
                                                               NULL) == RX_COMMAND_CLEAR_SLST) {
                program = [[NSDictionary alloc] initWithObjectsAndKeys:
                    [program objectForKey:RXScriptProgramKey], RXScriptProgramKey,
                    [NSNumber numberWithUnsignedShort:opcode_count - 1], RXScriptOpcodeCountKey,
                    nil];
                
                NSMutableDictionary* mutable_script = [hotspot_scripts mutableCopy];
                [mutable_script setObject:[NSArray arrayWithObject:program] forKey:RXMouseDownScriptKey];
                [program release];
                
                [hotspot_scripts release];
                hotspot_scripts = mutable_script;
            }
        }
        // WORKAROUND: patch hotspot 16 on pspit 31 to reset pelevcombo to 0 when the combination is wrong
        else if ([_descriptor isCardWithRMAP:15632 stackName:@"pspit"] && hspt_record->blst_id == 16) {
            NSDictionary* program = [[hotspot_scripts objectForKey:RXMouseDownScriptKey] objectAtIndex:0];
            RXScriptCompiler* comp = [[RXScriptCompiler alloc] initWithCompiledScript:program];
            NSMutableArray* dp = [comp decompiledScript];
            
            NSDictionary* opcode = [dp lastObject];
            if (RX_OPCODE_COMMAND_EQ(opcode, RX_COMMAND_BRANCH)) {
                NSDictionary* case0 = [[opcode objectForKey:@"cases"] objectAtIndex:0];
                if (RX_BRANCH_VAR_NAME_EQ(opcode, @"pelevcombo") && RX_CASE_VAL_EQ(case0, 5)) {
                    // insert a default case to the branch that will set pelevcombo to 0
                    NSArray* block = [NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:
                            [NSNumber numberWithUnsignedShort:RX_COMMAND_SET_VARIABLE], @"command",
                            [NSArray arrayWithObjects:
                                [NSNumber numberWithUnsignedShort:[_parent varIndexForName:@"pelevcombo"]],
                                [NSNumber numberWithUnsignedShort:0],
                                nil], @"args",
                            nil]];
                    
                    case0 = [NSDictionary dictionaryWithObjectsAndKeys:
                        [NSNumber numberWithUnsignedShort:0xffff], @"value",
                        block, @"block",
                        nil];
                    [[opcode objectForKey:@"cases"] addObject:case0];
                }
            }
            
            [comp setDecompiledScript:dp];
            
            NSMutableDictionary* mutable_script = [hotspot_scripts mutableCopy];
            [mutable_script setObject:[NSArray arrayWithObject:[comp compiledScript]] forKey:RXMouseDownScriptKey];
            
            [hotspot_scripts release];
            hotspot_scripts = mutable_script;
            
            [comp release];
        }
        // WORKAROUND: tweak hotspot "raisehandle" on tspit 138 (29539) to have the open-hand cursor
        else if ([_descriptor isCardWithRMAP:29539 stackName:@"tspit"] && hotspotName && [hotspotName isEqualToString:@"raisehandle"]) {
            hspt_record->mouse_cursor = RX_CURSOR_OPEN_HAND;
        }
        // WORKAROUND: tweak hotspot "forward" on jspit 609 (167117) to have the open-hand cursor
        else if ([_descriptor isCardWithRMAP:167117 stackName:@"jspit"] && hotspotName && [hotspotName isEqualToString:@"forward"]) {
            hspt_record->mouse_cursor = RX_CURSOR_OPEN_HAND;
        }
        // WORKAROUND: tweak hotspot "open" on bspit 163 (85071) to have the open-hand cursor
        else if ([_descriptor isCardWithRMAP:85071 stackName:@"bspit"] && hotspotName && [hotspotName isEqualToString:@"open"]) {
            hspt_record->mouse_cursor = RX_CURSOR_OPEN_HAND;
        }
        
        // allocate the hotspot object
        RXHotspot* hs = [[RXHotspot alloc] initWithIndex:hspt_record->index
                                                      ID:hspt_record->blst_id
                                                    rect:hspt_record->rect
                                                cursorID:hspt_record->mouse_cursor
                                                  script:hotspot_scripts];
        if (hotspotName) {
            [hs setName:hotspotName];
            NSMapInsert(_hotspots_name_map, [hs name], hs);
        }
        
        uintptr_t key = hspt_record->blst_id;
        NSMapInsert(_hotspotsIDMap, (void*)key, hs);
        [_hotspots addObject:hs];
        
        [hs release];
        [hotspot_scripts release];
    }
    
    // don't need the HSPT data anymore
    free(list_data);
    
    fh = [_parent fileWithResourceType:@"BLST" ID:[_descriptor ID]];
    if (!fh)
        @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                       reason:@"Could not open the card's corresponding BLST resource."
                                     userInfo:nil];
    
    list_data_size = (size_t)[fh length];
    if (_blstData)
        free(_blstData);
    _blstData = malloc(list_data_size);
    
    // read the data from the archive
    if ([fh readDataToEndOfFileInBuffer:_blstData error:&error] == -1)
        @throw [NSException exceptionWithName:@"RXRessourceIOException"
                                       reason:@"Could not read the card's corresponding BLST ressource."
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    
    _hotspotControlRecords = (struct rx_blst_record*)BUFFER_OFFSET(_blstData, sizeof(uint16_t));
    
    // byte order (and debug)
#if defined(__LITTLE_ENDIAN__) || (defined(DEBUG) && DEBUG > 1)
    uint16_t blstCount = CFSwapInt16BigToHost(*(uint16_t*)_blstData);
    for (list_index = 0; list_index < blstCount; list_index++) {
        struct rx_blst_record* record = _hotspotControlRecords + list_index;
        
#if defined(__LITTLE_ENDIAN__)
        record->index = CFSwapInt16(record->index);
        record->enabled = CFSwapInt16(record->enabled);
        record->hotspot_id = CFSwapInt16(record->hotspot_id);
#endif // defined(__LITTLE_ENDIAN__)
        
#if defined(DEBUG) && DEBUG > 1
        RXOLog(@"blst record %u: index=%hd, enabled=%hd, hotspot_id=%hd", list_index, record->index, record->enabled, record->hotspot_id);
#endif // defined(DEBUG) && DEBUG > 1
    }
#endif // defined(__LITTLE_ENDIAN__) || (defined(DEBUG) && DEBUG > 1)
}

- (void)_loadSpecialEffects {
    NSError* error;
    MHKFileHandle* fh;
    void* list_data;
    size_t list_data_size;
    uint16_t list_index;
    
    fh = [_parent fileWithResourceType:@"FLST" ID:[_descriptor ID]];
    if (!fh)
        @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                       reason:@"Could not open the card's corresponding FLST resource."
                                     userInfo:nil];
    
    list_data_size = (size_t)[fh length];
    list_data = malloc(list_data_size);
    
    // read the data from the archive
    if ([fh readDataToEndOfFileInBuffer:list_data error:&error] == -1)
        @throw [NSException exceptionWithName:@"RXRessourceIOException"
                                       reason:@"Could not read the card's corresponding FLST ressource."
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    
    _flstCount = CFSwapInt16BigToHost(*(uint16_t*)list_data);
    _sfxes = (rx_card_sfxe*)malloc(sizeof(rx_card_sfxe) * _flstCount);
    
    struct rx_flst_record* flstRecordPointer = (struct rx_flst_record*)BUFFER_OFFSET(list_data, sizeof(uint16_t));
    for (list_index = 0; list_index < _flstCount; list_index++) {
        struct rx_flst_record* record = flstRecordPointer + list_index;
        
#if defined(__LITTLE_ENDIAN__)
        record->index = CFSwapInt16(record->index);
        record->sfxe_id = CFSwapInt16(record->sfxe_id);
        record->u0 = CFSwapInt16(record->u0);
#endif
        
        // open the corresponding SFXE resource
        MHKFileHandle* sfxeHandle = [_parent fileWithResourceType:@"SFXE" ID:record->sfxe_id];
        if (!sfxeHandle)
            @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                           reason:@"Could not open a required SFXE resource."
                                         userInfo:nil];
        
        // get the size of the SFXE resource and allocate the sfxe's record buffer
        size_t sfxe_size = (size_t)[sfxeHandle length];
        assert(sfxe_size >= sizeof(struct rx_sfxe_record*));
        
        rx_card_sfxe* sfxe = _sfxes + list_index;
        sfxe->record = (struct rx_sfxe_record*)malloc(sfxe_size);
        
        // read the data from the archive
        if ([sfxeHandle readDataToEndOfFileInBuffer:(void*)sfxe->record error:&error] == -1)
            @throw [NSException exceptionWithName:@"RXRessourceIOException"
                                           reason:@"Could not read a required SFXE resource."
                                         userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
        
#if defined(__LITTLE_ENDIAN__)
        // byte swap on litle endian architectures
        sfxe->record->magic = CFSwapInt16(sfxe->record->magic);
        sfxe->record->frame_count = CFSwapInt16(sfxe->record->frame_count);
        sfxe->record->offset_table = CFSwapInt32(sfxe->record->offset_table);
        sfxe->record->rect = rx_swap_core_rect(sfxe->record->rect);
        sfxe->record->fps = CFSwapInt16(sfxe->record->fps);
        sfxe->record->u0 = CFSwapInt16(sfxe->record->u0);
        sfxe->record->alt_rect = rx_swap_core_rect(sfxe->record->alt_rect);
        sfxe->record->u1 = CFSwapInt16(sfxe->record->u1);
        sfxe->record->alt_frame_count = CFSwapInt16(sfxe->record->alt_frame_count);
        sfxe->record->u2 = CFSwapInt32(sfxe->record->u2);
        sfxe->record->u3 = CFSwapInt32(sfxe->record->u3);
        sfxe->record->u4 = CFSwapInt32(sfxe->record->u4);
        sfxe->record->u5 = CFSwapInt32(sfxe->record->u5);
        sfxe->record->u6 = CFSwapInt32(sfxe->record->u6);
#endif
        
        // alias the offset table for convenience
        sfxe->offsets = (uint32_t*)BUFFER_OFFSET(sfxe->record, sfxe->record->offset_table);

#if defined(__LITTLE_ENDIAN__)
        // byte swap the offsets and the program
        for (uint16_t fi = 0; fi < sfxe->record->frame_count; fi++) {
            sfxe->offsets[fi] = CFSwapInt32(sfxe->offsets[fi]);
            
            uint16_t* mp = (uint16_t*)BUFFER_OFFSET(sfxe->record, sfxe->offsets[fi]);
            *mp = CFSwapInt16(*mp);
            while (*mp != 4) {
                if (*mp == 3) {
                    mp[1] = CFSwapInt16(mp[1]);
                    mp[2] = CFSwapInt16(mp[2]);
                    mp[3] = CFSwapInt16(mp[3]);
                    mp[4] = CFSwapInt16(mp[4]);
                    mp += 4;
                } else if (*mp != 1)
                    abort();
                
                mp++;
                *mp = CFSwapInt16(*mp);
            }
            
            assert(mp <= (uint16_t*)BUFFER_OFFSET(sfxe->record, sfxe_size));
        }
#endif
    }
    
    // don't need the FLST data anymore
    free(list_data);
}

- (void)_loadSounds {
    NSError* error;
    MHKFileHandle* fh;
    void* list_data;
    size_t list_data_size;
    uint16_t list_index;
    
    fh = [_parent fileWithResourceType:@"SLST" ID:[_descriptor ID]];
    if (!fh)
        @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                       reason:@"Could not open the card's corresponding SLST resource."
                                     userInfo:nil];
    
    list_data_size = (size_t)[fh length];
    list_data = malloc(list_data_size);
    
    // read the data from the archive
    if ([fh readDataToEndOfFileInBuffer:list_data error:&error] == -1)
        @throw [NSException exceptionWithName:@"RXRessourceIOException"
                                       reason:@"Could not read the card's corresponding SLST ressource."
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    
    // how many sound groups do we have?
    uint16_t soundGroupCount = CFSwapInt16BigToHost(*(uint16_t*)list_data);
    uint16_t* slstRecordPointer = (uint16_t*)BUFFER_OFFSET(list_data, sizeof(uint16_t));
    _soundGroups = [[NSMutableArray alloc] initWithCapacity:soundGroupCount];
    
    // skip over index of first record (for loop takes care of skipping it afterwards)
    slstRecordPointer++;
    
    // load the sound groups
    for (list_index = 0; list_index < soundGroupCount; list_index++) {
        uint16_t soundCount = CFSwapInt16BigToHost(*slstRecordPointer);
        slstRecordPointer++;
        
        // create a sound group for the record
        RXSoundGroup* sgroup = [self newSoundGroupWithSLSTRecord:slstRecordPointer soundCount:soundCount swapBytes:YES];
        if (sgroup)
            [_soundGroups addObject:sgroup];
        [sgroup release];
        
        // move on to the next record's sound_count field
        slstRecordPointer = slstRecordPointer + (4 * soundCount) + 6;
    }
    
    // don't need the SLST data anymore
    free(list_data);
    
    // WORKAROUND: bspit 445 (dome linking book card) has no SLST record, which means when you link back to it from the
    // office age, the dome ambience won't kick in; we copy the sound group from that stack's dome card to fix the problem
    if ([_descriptor isCardWithRMAP:10439 stackName:@"bspit"] && soundGroupCount == 0) {
        // 110077 is the bspit dome card (which has the ambience sound)
        RXCardDescriptor* domeCardDesc = [[RXCardDescriptor alloc] initWithStack:_parent ID:[_parent cardIDFromRMAPCode:110077]];
        RXCard* domeCard = [[RXCard alloc] initWithCardDescriptor:domeCardDesc];
        [domeCard _loadSounds];
        
        [_soundGroups release];
        _soundGroups = [[domeCard soundGroups] copy];
        
        [domeCard release];
        [domeCardDesc release];
    }
    
}

- (void)load {
    if (_loaded)
        return;
#if defined(DEBUG)
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"loading card");
#endif
    
    [self _loadScripts];
    [self _loadPictures];
    [self _loadMovies];
    [self _loadHotspots];
    [self _loadSpecialEffects];
    [self _loadSounds];
    
    _loaded = YES;
}

#pragma mark -
#pragma mark dynamic loading

- (RXSoundGroup*)newSoundGroupWithSLSTRecord:(const uint16_t*)slst_record soundCount:(uint16_t)sound_count swapBytes:(BOOL)swap {
    RXSoundGroup* group = [RXSoundGroup new];
    
    // some useful pointers
    const uint16_t* group_parameters = slst_record + sound_count;
    const uint16_t* gain_parameters = group_parameters + 5;
    const uint16_t* pan_parameters = gain_parameters + sound_count;
    
    // fade flags
    uint16_t fade_flags = *group_parameters;
    if (swap)
        fade_flags = CFSwapInt16BigToHost(fade_flags);
    group->fadeOutRemovedSounds = (fade_flags & 0x0001) ? YES : NO;
    group->fadeInNewSounds = (fade_flags & 0x0002) ? YES : NO;
    
    // loop flag
    uint16_t loop = *(group_parameters + 1);
    if (swap)
        loop = CFSwapInt16BigToHost(loop);
    group->loop = (loop) ? YES : NO;
    
    // group gain
    uint16_t integer_gain = *(group_parameters + 2);
    if (swap)
        integer_gain = CFSwapInt16BigToHost(integer_gain);
    float gain = (float)integer_gain / kRXSoundGainDivisor;
    group->gain = gain;
    
    uint16_t sound_index = 0;
    for (; sound_index < sound_count; sound_index++) {
        uint16_t sound_id = *(slst_record + sound_index);
        if (swap)
            sound_id = CFSwapInt16BigToHost(sound_id);
        
        integer_gain = *(gain_parameters + sound_index);
        if (swap)
            integer_gain = CFSwapInt16BigToHost(integer_gain);
        gain = (float)integer_gain / kRXSoundGainDivisor;
        
        int16_t integer_pan = *((int16_t*)(pan_parameters + sound_index));
        if (swap)
            integer_pan = (int16_t)CFSwapInt16BigToHost(integer_pan);
        float pan = 0.5f + ((float)integer_pan / 200.0f);
        
        [group addSoundWithStack:_parent ID:sound_id gain:gain pan:pan];
    }
    
#if defined(DEBUG) && DEBUG > 1
    RXOLog(@"created sound group: %@", group);
#endif
    return group;
}

- (RXMovie*)loadMovieWithMLSTRecord:(struct rx_mlst_record*)mlst {
    // sometimes volume > 255, so fix it up here
    if (mlst->volume > 255)
        mlst->volume = 255;
    
    // load the movie up
    CGPoint origin = CGPointMake(mlst->left, kRXCardViewportSize.height - mlst->top);
    MHKArchive* archive = [[_parent fileWithResourceType:@"tMOV" ID:mlst->movie_id] archive];
    RXMovieProxy* movie_proxy = [[RXMovieProxy alloc] initWithArchive:archive
                                                                   ID:mlst->movie_id
                                                               origin:origin
                                                               volume:mlst->volume / 255.0f
                                                                 loop:((mlst->loop == 1) ? YES : NO)
                                                                owner:self];

    // add the movie to the movies array
    [_movies addObject:movie_proxy];
    [movie_proxy release];
    
    return [[(RXMovie*)movie_proxy retain] autorelease];
}

- (uint16_t)soundIDWithName:(NSString*)name {
    return [_parent soundIDForName:[NSString stringWithFormat:@"%hu_%@_1", [_descriptor ID], name]];
}

- (uint16_t)dataSoundIDWithName:(NSString*)name {
    return [_parent dataSoundIDForName:[NSString stringWithFormat:@"%hu_%@_1", [_descriptor ID], name]];
}

#pragma mark -
#pragma mark accessors

- (RXCardDescriptor*)descriptor {
    return [[_descriptor retain] autorelease];
}

- (RXStack*)parent {
    return [[[_descriptor parent] retain] autorelease];
}

- (GLuint)pictureCount {
    return _picture_count;
}

- (struct rx_plst_record*)pictureRecords {
    return (struct rx_plst_record*)BUFFER_OFFSET(_plst_data, sizeof(uint16_t));
}

- (NSDictionary*)scripts {
    return [[_card_scripts retain] autorelease];
}

- (NSArray*)hotspots {
    return [[_hotspots retain] autorelease];
}

- (NSMapTable*)hotspotsIDMap {
    return _hotspotsIDMap;
}

- (NSMapTable*)hotspotsNameMap {
    return _hotspots_name_map;
}

- (struct rx_blst_record*)hotspotControlRecords {
    return _hotspotControlRecords;
}

- (NSArray*)movies {
    return [[_movies retain] autorelease];
}

- (uint16_t*)movieCodes {
    return _mlstCodes;
}

- (NSArray*)soundGroups {
    return [[_soundGroups retain] autorelease];
}

- (rx_card_sfxe*)sfxes {
    return _sfxes;
}

@end
