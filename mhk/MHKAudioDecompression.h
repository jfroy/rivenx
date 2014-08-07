// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import <Foundation/NSObject.h>

#import <CoreAudio/CoreAudioTypes.h>

@class MHKFileHandle;

@protocol MHKAudioDecompression<NSObject>

// these properties are stable once initialized
@property (nonatomic, readonly) const AudioStreamBasicDescription* outputFormat NS_RETURNS_INNER_POINTER;
@property (nonatomic, readonly) uint64_t frameCount;
@property (nonatomic, readonly) uint32_t framesPerPacket;

// this propery changes whenever an ABL is filled or the decoder is reset
@property (nonatomic, readonly) uint64_t framePosition;

- (void)reset;
- (uint32_t)fillAudioBufferList:(AudioBufferList*)abl;

@end
