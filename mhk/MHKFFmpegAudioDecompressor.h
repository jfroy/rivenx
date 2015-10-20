// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "mhk/MHKAudioDecompression.h"

@class MHKSoundDescriptor;

@interface MHKFFmpegAudioDecompressor : NSObject<MHKAudioDecompression>

@property(nonatomic, readonly)
    const AudioStreamBasicDescription* outputFormat NS_RETURNS_INNER_POINTER;
@property(nonatomic, readonly) uint64_t frameCount;
@property(nonatomic, readonly) uint32_t framesPerPacket;
@property(nonatomic, readonly) uint64_t framePosition;

- (instancetype)initWithSoundDescriptor:(MHKSoundDescriptor*)sdesc
                             fileHandle:(MHKFileHandle*)fileHandle
                                  error:(NSError**)outError NS_DESIGNATED_INITIALIZER;

@end
