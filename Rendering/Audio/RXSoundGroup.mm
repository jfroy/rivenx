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
    if (sound->ID == self->ID && sound->parent == self->parent)
        return YES;
    return NO;
}

- (NSUInteger)hash {
    // WARNING: WILL BREAK ON 64-BIT
    return integer_pair_hash((int)parent, (int)ID);
}

- (NSString*)description {
    return [NSString stringWithFormat:@"%@ {parent=%@, ID=%hu, gain=%f, pan=%f, detach_timestamp=%qu, source=%p}",
        [super description], parent, ID, gain, pan, detach_timestamp, source];
}

- (id <MHKAudioDecompression>)audioDecompressor {
    if (!_decompressor)
        _decompressor = [[parent audioDecompressorWithID:ID] retain];
    return _decompressor;
}

@end


@implementation RXDataSound

- (id <MHKAudioDecompression>)audioDecompressor {
    if (!_decompressor)
        _decompressor = [[parent audioDecompressorWithDataID:ID] retain];
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

- (void)addSoundWithStack:(RXStack*)parent ID:(uint16_t)ID gain:(float)g pan:(float)p {
    RXSound* source = [RXSound new];
    source->parent = parent;
    source->ID = ID;
    source->gain = g;
    source->pan = p;
    
    [_sounds addObject:source];
    [source release];
}

- (NSSet*)sounds {
    return _sounds;
}

@end
