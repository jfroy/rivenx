//
//  RXSoundGroup.h
//  rivenx
//
//  Created by Jean-Francois Roy on 11/03/2006.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import <MHKKit/MHKAudioDecompression.h>

#import "Engine/RXStack.h"

#if defined(__cplusplus)
#import "Rendering/Audio/RXCardAudioSource.h"
#endif


@interface RXSound : NSObject {
    id <MHKAudioDecompression> _decompressor;

@public
    RXStack* parent;
    uint16_t twav_id;
    
    float gain;
    float pan;
    
    uint64_t detach_timestamp;
    
#if defined(__cplusplus)
    RX::CardAudioSource* source;
#else
    void* source;
#endif
}

- (id <MHKAudioDecompression>)audioDecompressor;
- (double)duration;

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

- (void)addSoundWithStack:(RXStack*)parent ID:(uint16_t)twav_id gain:(float)g pan:(float)p;
- (NSSet*)sounds;

@end
