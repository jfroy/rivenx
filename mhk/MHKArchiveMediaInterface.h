// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import <MHKKit/MHKArchive.h>

struct AVFormatContext;
@protocol MHKAudioDecompression;

@interface MHKBitmapDescriptor : NSObject
@property (nonatomic, readonly) int32_t width;
@property (nonatomic, readonly) int32_t height;
@end

@interface MHKSoundDescriptor : NSObject
@property (nonatomic, readonly) off_t samplesOffset;
@property (nonatomic, readonly) off_t samplesLength;
@property (nonatomic, readonly) uint16_t sampleRate;
@property (nonatomic, readonly) uint8_t sampleDepth;
@property (nonatomic, readonly) uint64_t frameCount;
@property (nonatomic, readonly) uint8_t channelCount;
@property (nonatomic, readonly) uint16_t compressionType;
@end

@interface MHKArchive (MHKArchiveBitmapAdditions)
- (MHKBitmapDescriptor*)bitmapDescriptorWithID:(uint16_t)bitmapID error:(NSError**)outError;
- (BOOL)loadBitmapWithID:(uint16_t)bitmapID bgraBuffer:(void*)bgraBuffer error:(NSError**)outError;
@end

@interface MHKArchive (MHKArchiveMovieAdditions)
- (struct AVFormatContext*)createAVFormatContextWithMovieID:(uint16_t)movieID error:(NSError**)outError;
@end

@interface MHKArchive (MHKArchiveSoundAdditions)
- (MHKSoundDescriptor*)soundDescriptorWithID:(uint16_t)soundID error:(NSError**)outError;
- (MHKFileHandle*)openSoundWithID:(uint16_t)soundID error:(NSError**)outError;
- (id<MHKAudioDecompression>)decompressorWithSoundID:(uint16_t)soundID error:(NSError**)outError;
@end
