//
//  RXStack.m
//  rivenx
//
//  Created by Jean-Francois Roy on 30/08/2005.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import <MHKKit/MHKKit.h>

#import "RXStack.h"
#import "RXCardDescriptor.h"

#import "RXWorldProtocol.h"
#import "RXArchiveManager.h"

static NSArray* _loadNAMEResourceWithID(MHKArchive* archive, uint16_t resourceID) {
    NSData* nameData = [archive dataWithResourceType:@"NAME" ID:resourceID];
    if (!nameData)
        return nil;
    
    uint16_t recordCount = CFSwapInt16BigToHost(*(const uint16_t*)[nameData bytes]);
    NSMutableArray* recordArray = [[NSMutableArray alloc] initWithCapacity:recordCount];
    
    const uint16_t* offsetBase = (uint16_t*)BUFFER_OFFSET([nameData bytes], sizeof(uint16_t));
    const uint8_t* stringBase = (uint8_t*)BUFFER_OFFSET([nameData bytes], sizeof(uint16_t) + (sizeof(uint16_t) * 2 * recordCount));
    
    for (uint16_t currentRecordIndex = 0; currentRecordIndex < recordCount; currentRecordIndex++) {
        uint16_t recordOffset = CFSwapInt16BigToHost(offsetBase[currentRecordIndex]);
        const unsigned char* entryBase = (const unsigned char*)stringBase + recordOffset;
        size_t recordLength = strlen((const char*)entryBase);
        
        // check for leading and closing 0xbd
        if (*entryBase == 0xbd) {
            entryBase++;
            recordLength--;
        }
        
        if (*(entryBase + recordLength - 1) == 0xbd)
            recordLength--;
        
        NSString* record = [[NSString alloc] initWithBytes:entryBase length:recordLength encoding:NSASCIIStringEncoding];
        [recordArray addObject:record];
        [record release];
    }
    
    return recordArray;
}


@interface RXStack (RXStackPrivate)
- (void)_load;
- (void)_tearDown;
@end

@implementation RXStack

// disable automatic KVC
+ (BOOL)accessInstanceVariablesDirectly {
    return NO;
}

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithKey:(NSString*)key error:(NSError**)error {
    if (!key)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Key string cannot be nil." userInfo:nil];
    
    self = [super init];
    if (!self)
        return nil;
    
    NSDictionary* descriptor = [g_world stackDescriptorForKey:key];
    if (!descriptor)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"No stack descriptor for stack key %@.", key] userInfo:nil];
    
    _entryCardID = [[descriptor objectForKey:@"Entry"] unsignedShortValue];
    _key = [key copy];
    
    _dataArchives = [[NSMutableArray alloc] initWithCapacity:3];
    _soundArchives = [[NSMutableArray alloc] initWithCapacity:1];
    
    RXArchiveManager* sam = [RXArchiveManager sharedArchiveManager];
    
    // load the data archives
    NSArray* archives = [sam dataArchivesForStackKey:_key error:error];
    if (!archives || [archives count] == 0) {
        [self release];
        return nil;
    }
    [_dataArchives addObjectsFromArray:archives];
#if defined(DEBUG)
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"data archives: %@", _dataArchives);
#endif
    
    // load the sound archives
    archives = [sam soundArchivesForStackKey:_key error:error];
    if (!archives || [archives count] == 0) {
        [self release];
        return nil;
    }
    [_soundArchives addObjectsFromArray:archives];
#if defined(DEBUG)
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"sound archives: %@", _soundArchives);
#endif
    
    // the master archive is the one that contains the RMAP and NAME data
    NSDictionary* rmapDescriptor = nil;
    MHKArchive* masterDataArchive = nil;
    for (MHKArchive* archive in _dataArchives)
    {
        masterDataArchive = archive;
        rmapDescriptor = [[masterDataArchive valueForKey:@"RMAP"] objectAtIndexIfAny:0];
        if (rmapDescriptor)
            break;
    }
    if (!rmapDescriptor)
    {
        RXOLog2(kRXLoggingEngine, kRXLoggingLevelError, @"no RMAP data for stack '%@'", _key);
        RXOLog2(kRXLoggingEngine, kRXLoggingLevelMessage, @"data archives: %@", _dataArchives);
        RXOLog2(kRXLoggingEngine, kRXLoggingLevelMessage, @"sound archives: %@", _soundArchives);
        
        [self release];
        return nil;
    }
    
    // global stack data
    _cardNames = _loadNAMEResourceWithID(masterDataArchive, 1);
    _hotspotNames = _loadNAMEResourceWithID(masterDataArchive, 2);
    _externalNames = _loadNAMEResourceWithID(masterDataArchive, 3);
    _varNames = _loadNAMEResourceWithID(masterDataArchive, 4);
    _stackNames = _loadNAMEResourceWithID(masterDataArchive, 5);
    
    // rmap data
    uint16_t remapID = [[rmapDescriptor objectForKey:@"ID"] unsignedShortValue];
    _rmapData = [[masterDataArchive dataWithResourceType:@"RMAP" ID:remapID] retain];
    
#if defined(DEBUG)
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"stack entry card is %d", _entryCardID);
#endif
    
    return self;
}

- (void)_tearDown {
#if defined(DEBUG)
    RXOLog(@"tearing down");
#endif
    
    // release a bunch of objects
    [_cardNames release]; _cardNames = nil;
    [_hotspotNames release]; _hotspotNames = nil;
    [_externalNames release]; _externalNames = nil;
    [_varNames release]; _varNames = nil;
    [_stackNames release]; _stackNames = nil;
    [_rmapData release]; _rmapData = nil;
    
    [_soundArchives release]; _soundArchives = nil;
    [_dataArchives release]; _dataArchives = nil;
}

- (void)dealloc {
#if defined(DEBUG)
    RXOLog(@"deallocating");
#endif
    
    // tear done before we deallocate
    [self _tearDown];
    
    [_key release];
    
    [super dealloc];
}

- (NSString*)description {
    return [NSString stringWithFormat: @"%@{%@}", [super description], _key];
}

- (NSString*)debugName {
    return _key;
}

#pragma mark -

- (NSString*)key {
    return _key;
}

- (uint16_t)entryCardID {
    return _entryCardID;
}

- (NSUInteger)cardCount {
    NSUInteger count = 0;
    NSEnumerator* enumerator = [_dataArchives objectEnumerator];
    MHKArchive* archive;
    while ((archive = [enumerator nextObject]))
        count += [[archive valueForKeyPath:@"CARD.@count"] intValue];
    return count;
}

#pragma mark -

- (NSString*)cardNameAtIndex:(uint32_t)index {
    return (_cardNames) ? [_cardNames objectAtIndex:index] : nil;
}

- (NSString*)hotspotNameAtIndex:(uint32_t)index {
    return (_hotspotNames) ? [_hotspotNames objectAtIndex:index] : nil;
}

- (NSString*)externalNameAtIndex:(uint32_t)index {
    return (_externalNames) ? [_externalNames objectAtIndex:index] : nil;
}

- (NSString*)varNameAtIndex:(uint32_t)index {
    return (_varNames) ? [_varNames objectAtIndex:index] : nil;
}

- (uint32_t)varIndexForName:(NSString*)name {
    uint32_t n = (uint32_t)[_varNames count];
    for (uint32_t i = 0; i < n; i++)
        if ([name isEqualToString:[_varNames objectAtIndex:i]])
            return i;
    return UINT32_MAX;
}

- (NSString*)stackNameAtIndex:(uint32_t)index {
    return (_stackNames) ? [_stackNames objectAtIndex:index] : nil;
}

- (uint16_t)cardIDFromRMAPCode:(uint32_t)code {
    uint32_t* rmap_data = (uint32_t*)[_rmapData bytes];
    uint32_t* rmap_end = (uint32_t*)BUFFER_OFFSET([_rmapData bytes], [_rmapData length]);
    uint16_t card_id = 0;
#if defined(__LITTLE_ENDIAN__)
    code = CFSwapInt32(code);
#endif
    while (*(rmap_data + card_id) != code && (rmap_data + card_id) < rmap_end)
        card_id++;
    if (rmap_data == rmap_end)
        return 0;
    return card_id;
}

- (uint32_t)cardRMAPCodeFromID:(uint16_t)card_id {
    uint32_t* rmap_data = (uint32_t*)[_rmapData bytes];
    return CFSwapInt32BigToHost(rmap_data[card_id]);
}

- (id <MHKAudioDecompression>)audioDecompressorWithID:(uint16_t)soundID {
    id <MHKAudioDecompression> decompressor = nil;
    
    NSEnumerator* enumerator = [_soundArchives objectEnumerator];
    MHKArchive* archive;
    while ((archive = [enumerator nextObject])) {
        decompressor = [archive decompressorWithSoundID:soundID error:NULL];
        if (decompressor)
            break;
    }
    return decompressor;
}

- (id <MHKAudioDecompression>)audioDecompressorWithDataID:(uint16_t)soundID {
    id <MHKAudioDecompression> decompressor = nil;
    
    NSEnumerator* enumerator = [_dataArchives objectEnumerator];
    MHKArchive* archive;
    while ((archive = [enumerator nextObject])) {
        decompressor = [archive decompressorWithSoundID:soundID error:NULL];
        if (decompressor)
            break;
    }
    return decompressor;
}

- (uint16_t)soundIDForName:(NSString*)sound_name {
    NSEnumerator* enumerator = [_soundArchives objectEnumerator];
    MHKArchive* archive;
    while ((archive = [enumerator nextObject])) {
        NSDictionary* desc = [archive resourceDescriptorWithResourceType:@"tWAV" name:sound_name];
        if (desc)
            return [[desc objectForKey:@"ID"] unsignedShortValue];
    }
    return 0;
}

- (uint16_t)dataSoundIDForName:(NSString*)sound_name {
    NSEnumerator* enumerator = [_dataArchives objectEnumerator];
    MHKArchive* archive;
    while ((archive = [enumerator nextObject])) {
        NSDictionary* desc = [archive resourceDescriptorWithResourceType:@"tWAV" name:sound_name];
        if (desc)
            return [[desc objectForKey:@"ID"] unsignedShortValue];
    }
    return 0;
}

- (uint16_t)bitmapIDForName:(NSString*)bitmap_name {
    NSEnumerator* enumerator = [_dataArchives objectEnumerator];
    MHKArchive* archive;
    while ((archive = [enumerator nextObject])) {
        NSDictionary* desc = [archive resourceDescriptorWithResourceType:@"tBMP" name:bitmap_name];
        if (desc)
            return [[desc objectForKey:@"ID"] unsignedShortValue];
    }
    return 0;
}

- (MHKFileHandle*)fileWithResourceType:(NSString*)type ID:(uint16_t)ID {
    NSEnumerator* enumerator = [_dataArchives objectEnumerator];
    MHKArchive* archive;
    while ((archive = [enumerator nextObject])) {
        MHKFileHandle* file = [archive openResourceWithResourceType:type ID:ID];
        if (file)
            return file;
    }
    
    return nil;
}

- (NSData*)dataWithResourceType:(NSString*)type ID:(uint16_t)ID {
    MHKFileHandle* file = [self fileWithResourceType:type ID:ID];
    if (file)
        return [file readDataToEndOfFile:NULL];
    return nil;
}

@end
