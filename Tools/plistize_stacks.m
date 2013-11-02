#import "Base/RXBase.h"
#import <MHKKit/MHKKit.h>

#define BUFFER_OFFSET(buffer, bytes) (__typeof__(buffer))((uint8_t*)(buffer) + (bytes))
#define BUFFER_NOFFSET(buffer, bytes) (__typeof__(buffer))((uint8_t*)(buffer) - (bytes))

static const NSString* k_eventSelectors[] = {
    @"mouseDown",
    @"mouseDown2",
    @"mouseUp",
    @"mouseDownOrUpOrMoved",
    @"mouseTrack",
    @"mouseMoved",
    @"loading",
    @"leaving",
    @"UNKNOWN - TYPE 8",
    @"rendering",
    @"priming"
};


static __inline__ NSPoint decodeRivenPoint(const void* rivenPointPtr) {
    int16_t x = CFSwapInt16BigToHost(*(const int16_t *)rivenPointPtr);
    int16_t y = CFSwapInt16BigToHost(*(const int16_t *)BUFFER_OFFSET(rivenPointPtr, 2));
    return NSMakePoint(x, y);
}

static __inline__ NSRect decodeRivenRect(const void* rivenRectPtr) {
    NSPoint tl = decodeRivenPoint(rivenRectPtr);
    NSPoint br = decodeRivenPoint(BUFFER_OFFSET(rivenRectPtr, 4));
    return NSMakeRect(tl.x, tl.y, br.x - tl.x, br.y - tl.y);
}

static size_t rx_compute_riven_script_length(const void* script, uint16_t commandCount, bool byte_swap) {
    size_t scriptOffset = 0;
    
    uint16_t currentCommandIndex = 0;
    for (; currentCommandIndex < commandCount; currentCommandIndex++) {
        // command, argument count, arguments (all shorts)
        uint16_t commandNumber = *(const uint16_t*)BUFFER_OFFSET(script, scriptOffset);
        if (byte_swap) commandNumber = CFSwapInt16BigToHost(commandNumber);
        scriptOffset += 2;
        
        uint16_t argumentCount = *(const uint16_t*)BUFFER_OFFSET(script, scriptOffset);
        if (byte_swap) argumentCount = CFSwapInt16BigToHost(argumentCount);
        size_t argumentsOffset = 2 * (argumentCount + 1);
        scriptOffset += argumentsOffset;
        
        // need to do extra processing for command 8
        if (commandNumber == 8) {
            // arg 0 is the variable, arg 1 is the number of cases
            uint16_t caseCount = *(const uint16_t*)BUFFER_OFFSET(script, scriptOffset - argumentsOffset + 4);
            if (byte_swap) caseCount = CFSwapInt16BigToHost(caseCount);
            
            uint16_t currentCaseIndex = 0;
            for (; currentCaseIndex < caseCount; currentCaseIndex++) {
                // case variable value
                scriptOffset += 2;
                
                uint16_t caseCommandCount = *(const uint16_t*)BUFFER_OFFSET(script, scriptOffset);
                if (byte_swap) caseCommandCount = CFSwapInt16BigToHost(caseCommandCount);
                scriptOffset += 2;
                
                size_t caseCommandListLength = rx_compute_riven_script_length(BUFFER_OFFSET(script, scriptOffset), caseCommandCount, byte_swap);
                scriptOffset += caseCommandListLength;
            }
        }
    }
    
    return scriptOffset;
}

static NSDictionary* rx_decode_riven_script(const void* script, uint32_t* scriptLength) {
    // WARNING: THIS METHOD ASSUMES THE INPUT SCRIPT IS IN BIG ENDIAN
    
    // a script is composed of several events
    uint16_t eventCount = CFSwapInt16BigToHost(*(const uint16_t *)script);
    uint32_t scriptOffset = 2;
    
    // one array of Riven programs per event type
    uint32_t eventTypeCount = sizeof(k_eventSelectors) / sizeof(NSString *);
    uint16_t currentEventIndex = 0;
    NSMutableArray** eventProgramsPerType = (NSMutableArray**)malloc(sizeof(NSMutableArray*) * eventTypeCount);
    for (; currentEventIndex < eventTypeCount; currentEventIndex++) eventProgramsPerType[currentEventIndex] = [[NSMutableArray alloc] initWithCapacity:eventCount];
    
    // process the programs
    for (currentEventIndex = 0; currentEventIndex < eventCount; currentEventIndex++) {
        // event type, command count
        uint16_t eventCode = CFSwapInt16BigToHost(*(const uint16_t *)BUFFER_OFFSET(script, scriptOffset));
        scriptOffset += 2;
        uint16_t commandCount = CFSwapInt16BigToHost(*(const uint16_t *)BUFFER_OFFSET(script, scriptOffset));
        scriptOffset += 2;
        
        // program length
        size_t programLength = rx_compute_riven_script_length(BUFFER_OFFSET(script, scriptOffset), commandCount, true);
        
        // allocate a storage buffer for the program and swap it if needed
        uint16_t* programStore = (uint16_t*)malloc(programLength);
        memcpy(programStore, BUFFER_OFFSET(script, scriptOffset), programLength);
#if defined(__LITTLE_ENDIAN__)
        uint32_t shortCount = programLength / 2;
        while (shortCount > 0) {
            programStore[shortCount - 1] = CFSwapInt16BigToHost(programStore[shortCount - 1]);
            shortCount--;
        }
#endif
        
        // store the program in an NSData object
        NSData* program = [[NSData alloc] initWithBytesNoCopy:programStore length:programLength freeWhenDone:YES];
        scriptOffset += programLength;
        
        // program descriptor
        NSDictionary* programDescriptor = [[NSDictionary alloc] initWithObjectsAndKeys:program, @"program", 
            [NSNumber numberWithUnsignedShort:commandCount], @"opcodeCount", 
            nil];
        assert(eventCode < eventTypeCount);
        [eventProgramsPerType[eventCode] addObject:programDescriptor];
        
        [program release];
        [programDescriptor release];
    }
    
    // each event key holds an array of programs
    NSDictionary* scriptDictionary = [[NSDictionary alloc] initWithObjects:eventProgramsPerType forKeys:k_eventSelectors count:eventTypeCount];
    
    // release the program arrays now that they're in the dictionary
    for (currentEventIndex = 0; currentEventIndex < eventTypeCount; currentEventIndex++) [eventProgramsPerType[currentEventIndex] release];
    
    // release the program array array.
    free(eventProgramsPerType);
    
    // return total script length and script dictionary
    if (scriptLength) *scriptLength = scriptOffset;
    return scriptDictionary;
}

static NSArray* _loadNAMEResourceWithID(MHKArchive* archive, uint16_t resourceID) {
    NSData* nameData = [archive dataWithResourceType:@"NAME" ID:resourceID];
    if (!nameData) return nil;
    
    uint16_t recordCount = CFSwapInt16BigToHost(*(const uint16_t *)[nameData bytes]);
    NSMutableArray* recordArray = [[NSMutableArray alloc] initWithCapacity:recordCount];
    
    const uint16_t* offsetBase = (uint16_t *)BUFFER_OFFSET([nameData bytes], sizeof(uint16_t));
    const uint8_t* stringBase = (uint8_t *)BUFFER_OFFSET([nameData bytes], sizeof(uint16_t) + (sizeof(uint16_t) * 2 * recordCount));
    
    uint16_t currentRecordIndex = 0;
    for (; currentRecordIndex < recordCount; currentRecordIndex++) {
        uint16_t recordOffset = CFSwapInt16BigToHost(offsetBase[currentRecordIndex]);
        const unsigned char* entryBase = (const unsigned char *)stringBase + recordOffset;
        size_t recordLength = strlen((const char *)entryBase);
        
        // check for leading and closing 0xbd
        if (*entryBase == 0xbd) {
            entryBase++;
            recordLength--;
        }
        
        if (*(entryBase + recordLength - 1) == 0xbd) recordLength--;
        
        NSString* record = [[NSString alloc] initWithBytes:entryBase length:recordLength encoding:NSASCIIStringEncoding];
        [recordArray addObject:record];
        [record release];
    }
    
    return recordArray;
}

int main(int argc, const char * argv[]) {
    NSAutoreleasePool* pool1 = [[NSAutoreleasePool alloc] init];
    NSAutoreleasePool* pool2 = nil;

    if (argc < 2) {
        printf("usage: %s [Mohawk archive]\n", argv[1]);
        exit(1);
    }
    
    NSMutableArray* archives = [[NSMutableArray alloc] initWithCapacity:argc - 1];
    if (!archives) {
        printf("failed to allocate archives array\n");
        exit(1);
    }
    
    NSError* error = nil;
    
    int archive_index = 1;
    for (; archive_index < argc; archive_index++) {
        MHKArchive* archive = [[MHKArchive alloc] initWithPath:[NSString stringWithUTF8String:argv[archive_index]] error:&error];
        if (!archive) {
            printf("failed to open archive (%s)\n", [[error description] UTF8String]);
            exit(1);
        }
        
        [archives addObject:archive];
        [archive release];
    }
    
    MHKArchive* masterArchive = nil;
    for (archive_index = 0; archive_index < (int)[archives count]; archive_index++) {
        if ([[[archives objectAtIndex:archive_index] valueForKey:@"NAME"] count] > 0) {
            masterArchive = [archives objectAtIndex:archive_index];
            break;
        }
    }
    
    if(!masterArchive) {
        printf("the provided archives do not form a complete stack\n");
        exit(1);
    }
    
    printf("loading stack NAME data...\n");
    pool2 = [[NSAutoreleasePool alloc] init];
    NSArray* cardNames = _loadNAMEResourceWithID(masterArchive, 1);
    NSArray* hotspotNames = _loadNAMEResourceWithID(masterArchive, 2);
    NSArray* externalNames = _loadNAMEResourceWithID(masterArchive, 3);
    NSArray* varNames = _loadNAMEResourceWithID(masterArchive, 4);
    NSArray* stackNames = _loadNAMEResourceWithID(masterArchive, 5);
    [pool2 release];
    
    printf("%u CARD names, %u HSPT names, %u external names, %u variable names, %u stack names\n", [cardNames count], [hotspotNames count], [externalNames count], [varNames count], [stackNames count]);
    
    NSDictionary* rmapDescriptor = [[masterArchive valueForKey:@"RMAP"] objectAtIndex:0];
    uint16_t remapID = [[rmapDescriptor valueForKey:@"ID"] unsignedShortValue];
    NSData* rmapData = [masterArchive dataWithResourceType:@"RMAP" ID:remapID];
    
    for (archive_index = 0; archive_index < (int)[archives count]; archive_index++) {
        MHKArchive* archive = [archives objectAtIndex:archive_index];
        printf("processing archive %d\n", archive_index + 1);
        
        NSArray* cards = [archive valueForKey:@"CARD"];
        if (!cards) continue;
        
        unsigned hsptCount = [[archive valueForKey:@"HSPT"] count];
        unsigned blstCount = [[archive valueForKey:@"BLST"] count];
        unsigned flstCount = [[archive valueForKey:@"FLST"] count];
        unsigned mlstCount = [[archive valueForKey:@"MLST"] count];
        unsigned plstCount = [[archive valueForKey:@"PLST"] count];
        unsigned slstCount = [[archive valueForKey:@"SLST"] count];
        
        printf("%u CARD, %u BLST, %u FLST, %u MLST, %u PLST, %u SLST, %u HSPT\n", [cards count], blstCount, flstCount, mlstCount, plstCount, slstCount, hsptCount);
        
        // create the output folder
        NSFileManager* fm = [NSFileManager defaultManager];
        NSString* dump_folder = [NSHomeDirectory() stringByAppendingPathComponent:@"mhk_card_dump"];
        [fm createDirectoryAtPath:dump_folder attributes:nil];
        dump_folder = [dump_folder stringByAppendingPathComponent:[[[archive url] path] lastPathComponent]];
        [fm createDirectoryAtPath:dump_folder attributes:nil];
        
        unsigned cardCount = [cards count];
        unsigned currentCardIndex = 0;
        
        printf("processing %d cards...\n", cardCount);
        for (; currentCardIndex < cardCount; currentCardIndex++) {
            pool2 = [[NSAutoreleasePool alloc] init];
            
            NSDictionary* cardResourceDescriptor = [cards objectAtIndex:currentCardIndex];
            NSMutableDictionary* cardDescriptor = [[NSMutableDictionary alloc] init];
            
            // native card information
            uint16_t cardResourceID = [[cardResourceDescriptor valueForKey:@"ID"] unsignedShortValue];
            NSData* cardData = [archive dataWithResourceType:@"CARD" ID:cardResourceID];
            
            int16_t nameIndex = CFSwapInt16BigToHost(*(const int16_t*)[cardData bytes]);
            NSString* cardName = (nameIndex > -1) ? (cardNames) ? [cardNames objectAtIndex:nameIndex] : nil : nil;
            
            uint16_t zipCard = CFSwapInt16BigToHost(*(const uint16_t*)BUFFER_OFFSET([cardData bytes], 2));
            NSNumber* zipCardNumber = [NSNumber numberWithBool:(zipCard) ? YES : NO];
            
            uint16_t rmapID = (rmapData) ? CFSwapInt16BigToHost(*(const uint16_t*)BUFFER_OFFSET([rmapData bytes], (cardResourceID * 4) + 2)) : 0;
            NSNumber* remapIDNumber = [NSNumber numberWithUnsignedShort:rmapID];
            
            // card events
            NSDictionary* cardEvents = rx_decode_riven_script(BUFFER_OFFSET([cardData bytes], 4), NULL);
            
            // card hotspots
            NSData* hotspotData = [archive dataWithResourceType:@"HSPT" ID:cardResourceID];
            const void* hostspotDataPtr = [hotspotData bytes];
            
            uint16_t hotspotCount = CFSwapInt16BigToHost(*(const uint16_t *)hostspotDataPtr);
            uint16_t currentHotspotIndex = 0;
            hostspotDataPtr = BUFFER_OFFSET(hostspotDataPtr, 2);
            
            NSMutableArray* hotspots = [[NSMutableArray alloc] initWithCapacity:hotspotCount];
            for (; currentHotspotIndex < hotspotCount; currentHotspotIndex++) {
                NSMutableDictionary* hostspotDescriptor = [[NSMutableDictionary alloc] init];
                
                uint16_t hotspotID = CFSwapInt16BigToHost(*(const uint16_t*)hostspotDataPtr);
                int16_t nameIndex = CFSwapInt16BigToHost(*(const int16_t*)BUFFER_OFFSET(hostspotDataPtr, 2));
                NSRect hotspotRect = decodeRivenRect(BUFFER_OFFSET(hostspotDataPtr, 4));
                uint16_t hotspotCursor = CFSwapInt16BigToHost(*(const int16_t*)BUFFER_OFFSET(hostspotDataPtr, 14));
                uint32_t scriptLength = 0;
                NSDictionary* hotspotEvents = rx_decode_riven_script(BUFFER_OFFSET(hostspotDataPtr, 22), &scriptLength);
                
                NSNumber* hotspotIDNumber = [NSNumber numberWithUnsignedShort:hotspotID];
                NSString* hotspotName = (nameIndex > -1) ? (hotspotNames) ? [hotspotNames objectAtIndex:nameIndex] : nil : nil;
                NSString* hotspotRectString = NSStringFromRect(hotspotRect);
                NSNumber* hotspotCursorNumber = [NSNumber numberWithUnsignedShort:hotspotCursor];
                
                // build the hotspot descriptor dictionary
                [hostspotDescriptor setValue:hotspotEvents forKey:@"Events"];
                [hostspotDescriptor setValue:hotspotIDNumber forKey:@"ID"];
                [hostspotDescriptor setValue:hotspotName forKey:@"Name"];
                [hostspotDescriptor setValue:hotspotRectString forKey:@"Rectangle"];
                [hostspotDescriptor setValue:hotspotCursorNumber forKey:@"Cursor"];
                
                [hotspots addObject:hostspotDescriptor];
                
                [hotspotEvents release];
                [hostspotDescriptor release];
                
                hostspotDataPtr = BUFFER_OFFSET(hostspotDataPtr, 22 + scriptLength);
            }
            
            // card misc information (all the list resources)
            NSData* listData = [archive dataWithResourceType:@"BLST" ID:cardResourceID];
            const void* listDataPtr = [listData bytes];
            
            uint16_t listCount = CFSwapInt16BigToHost(*(const uint16_t*)listDataPtr);
            uint16_t currentListIndex = 0;
            listDataPtr = BUFFER_OFFSET(listDataPtr, 2);
            
            // BLST
            NSMutableArray* blstEntries = [[NSMutableArray alloc] initWithCapacity:listCount];
            for(; currentListIndex < listCount; currentListIndex++) {
                NSMutableDictionary* listDescriptor = [[NSMutableDictionary alloc] init];
                uint16_t field_index = CFSwapInt16BigToHost(*(const uint16_t*)listDataPtr);
                uint16_t field_enabled = CFSwapInt16BigToHost(*(const uint16_t*)BUFFER_OFFSET(listDataPtr, 2));
                uint16_t field_id = CFSwapInt16BigToHost(*(const uint16_t*)BUFFER_OFFSET(listDataPtr, 4));
                
                NSNumber* field_index_o = [NSNumber numberWithUnsignedShort:field_index];
                NSNumber* field_enabled_o = [NSNumber numberWithUnsignedShort:field_enabled];
                NSNumber* field_id_o = [NSNumber numberWithUnsignedShort:field_id];
                
                [listDescriptor setValue:field_index_o forKey:@"Index"];
                [listDescriptor setValue:field_enabled_o forKey:@"Enabled"];
                [listDescriptor setValue:field_id_o forKey:@"ID"];
                
                [blstEntries addObject:listDescriptor];
                [listDescriptor release];
                
                listDataPtr = BUFFER_OFFSET(listDataPtr, 6);
            }
            
            // PLST
            listData = [archive dataWithResourceType:@"PLST" ID:cardResourceID];
            listDataPtr = [listData bytes];
            
            listCount = CFSwapInt16BigToHost(*(const uint16_t *)listDataPtr);
            currentListIndex = 0;
            listDataPtr = BUFFER_OFFSET(listDataPtr, 2);
            
            NSMutableArray* plstEntries = [[NSMutableArray alloc] initWithCapacity:listCount];
            for(; currentListIndex < listCount; currentListIndex++) {
                NSMutableDictionary* listDescriptor = [[NSMutableDictionary alloc] init];
                uint16_t field_index = CFSwapInt16BigToHost(*(const uint16_t*)listDataPtr);
                uint16_t field_bitmap_id = CFSwapInt16BigToHost(*(const uint16_t*)BUFFER_OFFSET(listDataPtr, 2));
                NSRect field_display_rect = decodeRivenRect(BUFFER_OFFSET(listDataPtr, 4));
                
                NSNumber* field_index_o = [NSNumber numberWithUnsignedShort:field_index];
                NSNumber* field_bitmap_id_o = [NSNumber numberWithUnsignedShort:field_bitmap_id];
                NSString* field_display_rect_o = NSStringFromRect(field_display_rect);
                
                [listDescriptor setValue:field_index_o forKey:@"Index"];
                [listDescriptor setValue:field_bitmap_id_o forKey:@"ID"];
                [listDescriptor setValue:field_display_rect_o forKey:@"Destination"];
                
                [plstEntries addObject:listDescriptor];
                [listDescriptor release];
                
                listDataPtr = BUFFER_OFFSET(listDataPtr, 12);
            }
            
            // MLST
            listData = [archive dataWithResourceType:@"MLST" ID:cardResourceID];
            listDataPtr = [listData bytes];
            
            listCount = CFSwapInt16BigToHost(*(const uint16_t*)listDataPtr);
            currentListIndex = 0;
            listDataPtr = BUFFER_OFFSET(listDataPtr, 2);
            
            NSMutableArray* mlstEntries = [[NSMutableArray alloc] initWithCapacity:listCount];
            for(; currentListIndex < listCount; currentListIndex++) {
                NSMutableDictionary* listDescriptor = [[NSMutableDictionary alloc] init];
                uint16_t field_index = CFSwapInt16BigToHost(*(const uint16_t*)listDataPtr);
                uint16_t field_movie_id = CFSwapInt16BigToHost(*(const uint16_t*)BUFFER_OFFSET(listDataPtr, 2));
                uint16_t field_code = CFSwapInt16BigToHost(*(const uint16_t*)BUFFER_OFFSET(listDataPtr, 4));
                NSPoint field_display_point = decodeRivenPoint(BUFFER_OFFSET(listDataPtr, 6));
                uint16_t field_repeat = CFSwapInt16BigToHost(*(const uint16_t*)BUFFER_OFFSET(listDataPtr, 16));
                uint16_t field_gain = CFSwapInt16BigToHost(*(const uint16_t*)BUFFER_OFFSET(listDataPtr, 18));
                
                NSNumber* field_index_o = [NSNumber numberWithUnsignedShort:field_index];
                NSNumber* field_movie_id_o = [NSNumber numberWithUnsignedShort:field_movie_id];
                NSNumber* field_code_o = [NSNumber numberWithUnsignedShort:field_code];
                NSString* field_display_point_o = NSStringFromPoint(field_display_point);
                NSNumber* field_repeat_o = [NSNumber numberWithUnsignedShort:field_repeat];
                NSNumber* field_gain_o = [NSNumber numberWithUnsignedShort:field_gain];
                
                [listDescriptor setValue:field_index_o forKey:@"Index"];
                [listDescriptor setValue:field_movie_id_o forKey:@"ID"];
                [listDescriptor setValue:field_code_o forKey:@"Code"];
                [listDescriptor setValue:field_display_point_o forKey:@"Destination"];
                [listDescriptor setValue:field_repeat_o forKey:@"Repeat"];
                [listDescriptor setValue:field_gain_o forKey:@"Gain"];
                
                [mlstEntries addObject:listDescriptor];
                [listDescriptor release];
                
                listDataPtr = BUFFER_OFFSET(listDataPtr, 22);
            }
            
            // build the card descriptor dictionary
            [cardDescriptor setValue:[cardResourceDescriptor valueForKey:@"ID"] forKey:@"ID"];
            [cardDescriptor setValue:[cardResourceDescriptor valueForKey:@"Name"] forKey:@"Name"];
            
            [cardDescriptor setValue:plstEntries forKey:@"Bitmaps"];
            [cardDescriptor setValue:cardName forKey:@"Card Name"];
            [cardDescriptor setValue:cardEvents forKey:@"Events"];
            [cardDescriptor setValue:hotspots forKey:@"Hotspots"];
            [cardDescriptor setValue:blstEntries forKey:@"Hotspots Control"];
            [cardDescriptor setValue:remapIDNumber forKey:@"RMAP ID"];
            [cardDescriptor setValue:mlstEntries forKey:@"Movies"];
            [cardDescriptor setValue:zipCardNumber forKey:@"ZIP"];
            
            [cardDescriptor writeToFile:[dump_folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.plist", currentCardIndex]] atomically:NO];
            
            [mlstEntries release];
            [blstEntries release];
            [plstEntries release];
            [hotspots release];
            [cardEvents release];
            [cardDescriptor release];
            
            [pool2 release];
        }
    }
    
    [stackNames release];
    [varNames release];
    [externalNames release];
    [hotspotNames release];
    [cardNames release];
    
    [archives release];
    
    [pool1 release];
    return 0;
}
