//
//  RXSoundGroup.mm
//  rivenx
//
//  Created by Jean-Francois Roy on 11/03/2006.
//  Copyright 2006 MacStorm. All rights reserved.
//

#import "Rendering/Audio/RXSoundGroup.h"
#import "Utilities/integer_pair_hash.h"


@implementation RXSound

- (void)dealloc {
    [_decompressor release];
    [super dealloc];
}

- (BOOL)isEqual:(id)anObject {
    if (![anObject isKindOfClass:[self class]])
        return NO;
    
    RXSound* sound = (RXSound*)anObject;
    if (sound->twav_id == self->twav_id && sound->parent == self->parent)
        return YES;
    
    return NO;
}

- (NSUInteger)hash {
    // WARNING: WILL BREAK ON 64-BIT
    return integer_pair_hash((int)parent, (int)twav_id);
}

- (NSString*)description {
    return [NSString stringWithFormat:@"%@ {parent=%@, ID=%hu, gain=%f, pan=%f, detach_timestamp=%qu, source=%p}",
        [super description], parent, twav_id, gain, pan, detach_timestamp, source];
}

- (id <MHKAudioDecompression>)audioDecompressor {
    if (!_decompressor)
        _decompressor = [[parent audioDecompressorWithID:twav_id] retain];
    return _decompressor;
}

- (double)duration {
    if (!source)
        return 0.0;
    return source->Duration();
}

@end


@implementation RXDataSound

- (id <MHKAudioDecompression>)audioDecompressor {
    if (!_decompressor)
        _decompressor = [[parent audioDecompressorWithDataID:twav_id] retain];
    return _decompressor;
}

- (BOOL)isEqual:(id)anObject {
    return (anObject == self) ? YES : NO;
}

- (NSUInteger)hash {
    return (NSUInteger)self;
}

@end


@implementation RXSoundGroup

- (id)init {
    self = [super init];
    if (!self)
        return nil;
    
    _sounds = [NSMutableSet new];
    
    return self;
}

- (void)dealloc {
#if defined(DEBUG) && DEBUG > 1
    RXOLog(@"deallocating");
#endif
    
    [_sounds release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat: @"%@ {fadeOutRemovedSounds=%d, fadeInNewSounds=%d, loop=%d, gain=%f, %d sounds}",
        [super description], fadeOutRemovedSounds, fadeInNewSounds, loop, gain, [_sounds count]];
}

- (void)addSoundWithStack:(RXStack*)parent ID:(uint16_t)twav_id gain:(float)g pan:(float)p {
    RXSound* sound = [RXSound new];
    sound->parent = parent;
    sound->twav_id = twav_id;
    sound->gain = g;
    sound->pan = p;
    
    [_sounds addObject:sound];
    [sound release];
}

- (NSSet*)sounds {
    return _sounds;
}

@end
