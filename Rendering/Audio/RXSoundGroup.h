//
//  RXSoundGroup.h
//  rivenx
//
//  Created by Jean-Francois Roy on 11/03/2006.
//  Copyright 2006 MacStorm. All rights reserved.
//

#import <MHKKit/MHKAudioDecompression.h>

#import "RXStack.h"
#import "RXCardAudioSource.h"


@interface RXSound : NSObject {
    id <MHKAudioDecompression> _decompressor;

@public
    RXStack* parent;
    uint16_t ID;
    
    float gain;
    float pan;
    
    uint64_t detach_timestamp;
    
    RX::CardAudioSource* source;
}

- (id <MHKAudioDecompression>)audioDecompressor;

@end

@interface RXDataSound : RXSound {}
@end


@interface RXSoundGroup : NSObject {
@public
    BOOL fadeOutRemovedSounds;
    BOOL fadeInNewSounds;
    BOOL loop;
    float gain;
    
@private
    NSMutableSet* _sounds;
}

- (void)addSoundWithStack:(RXStack*)parent ID:(uint16_t)ID gain:(float)g pan:(float)p;
- (NSSet*)sounds;

@end
