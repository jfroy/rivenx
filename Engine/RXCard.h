//
//  RXCard.h
//  rivenx
//
//  Created by Jean-Francois Roy on 30/08/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import <mach/semaphore.h>

#import <Cocoa/Cocoa.h>

#import "Engine/RXCardDescriptor.h"
#import "Engine/RXCoreStructures.h"
#import "Engine/RXHotspot.h"
#import "Engine/RXCardProtocols.h"


@interface RXCard : NSObject {
    RXCardDescriptor* _descriptor;
    RXStack* _parent;
    BOOL _loaded;
    
    // scripts
    NSDictionary* _card_scripts;
    
    // hotspots
    NSMutableArray* _hotspots;
    NSMapTable* _hotspotsIDMap;
    NSMapTable* _hotspots_name_map;
    void* _blstData;
    struct rx_blst_record* _hotspotControlRecords;
    
    // pictures
    struct rx_plst_record* _picture_records;
    uint32_t _picture_count;
    
    // movies
    NSMutableArray* _movies;
    uint16_t* _mlstCodes;
    
    // sound groups
    NSMutableArray* _soundGroups;
    
    // special effects
    uint16_t _flstCount;
    rx_card_sfxe* _sfxes;
}

- (id)initWithCardDescriptor:(RXCardDescriptor*)cardDescriptor;

- (RXCardDescriptor*)descriptor;
- (RXStack*)parent;
- (NSString*)name;

- (void)load;

- (NSDictionary*)scripts;
- (NSArray*)hotspots;
- (NSMapTable*)hotspotsIDMap;
- (NSMapTable*)hotspotsNameMap;
- (struct rx_blst_record*)hotspotControlRecords;

- (GLuint)pictureCount;
- (struct rx_plst_record*)pictureRecords;

- (NSArray*)movies;
- (uint16_t*)movieCodes;
- (NSArray*)soundGroups;

- (rx_card_sfxe*)sfxes;

- (RXSoundGroup*)newSoundGroupWithSLSTRecord:(const uint16_t*)slstRecord soundCount:(uint16_t)soundCount swapBytes:(BOOL)swapBytes;
- (RXMovie*)loadMovieWithMLSTRecord:(struct rx_mlst_record*)mlst;

@end
