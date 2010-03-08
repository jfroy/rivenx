//
//  RXStack.h
//  rivenx
//
//  Created by Jean-Francois Roy on 30/08/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MHKKit/MHKKit.h>


@interface RXStack : NSObject {
@private
    NSString* _key;
    
    NSMutableArray* _dataArchives;
    NSMutableArray* _soundArchives;
    
    // global stack data
    NSArray* _cardNames;
    NSArray* _hotspotNames;
    NSArray* _externalNames;
    NSArray* _varNames;
    NSArray* _stackNames;
    NSData* _rmapData;
    
    // card storage
    uint16_t _entryCardID;
}

- (id)initWithKey:(NSString*)key error:(NSError**)error;

- (NSString*)key;
- (uint16_t)entryCardID;

- (NSUInteger)cardCount;

- (NSString*)cardNameAtIndex:(uint32_t)index;
- (NSString*)hotspotNameAtIndex:(uint32_t)index;
- (NSString*)externalNameAtIndex:(uint32_t)index;
- (NSString*)varNameAtIndex:(uint32_t)index;
- (uint32_t)varIndexForName:(NSString*)name;
- (NSString*)stackNameAtIndex:(uint32_t)index;

- (uint16_t)cardIDFromRMAPCode:(uint32_t)code;
- (uint32_t)cardRMAPCodeFromID:(uint16_t)card_id;

- (id <MHKAudioDecompression>)audioDecompressorWithID:(uint16_t)soundID;
- (id <MHKAudioDecompression>)audioDecompressorWithDataID:(uint16_t)soundID;

- (uint16_t)soundIDForName:(NSString*)sound_name;
- (uint16_t)dataSoundIDForName:(NSString*)sound_name;
- (uint16_t)bitmapIDForName:(NSString*)bitmap_name;

- (MHKFileHandle*)fileWithResourceType:(NSString*)type ID:(uint16_t)ID;
- (NSData*)dataWithResourceType:(NSString*)type ID:(uint16_t)ID;

@end
