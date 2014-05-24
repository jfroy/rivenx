//
//  MHKArchiveMediaInterface.h
//  rivenx
//
//  Created by jfroy on 2/20/14.
//  Copyright (c) 2014 MacStorm. All rights reserved.
//

#if !defined(__LP64__)
#import <QuickTime/QuickTime.h>
#endif

#import <MHKKit/MHKArchive.h>

#import <MHKKit/mohawk_bitmap.h>
#import <MHKKit/mohawk_libav.h>
#import <MHKKit/mohawk_wave.h>
#import <MHKKit/MHKAudioDecompression.h>

#if !defined(__LP64__)
@interface MHKArchive (MHKArchiveQuickTimeAdditions)
- (Movie)movieWithID:(uint16_t)movieID error:(NSError**)errorPtr;
@end
#endif

@interface MHKArchive (MHKArchiveMovieAdditions)
- (AVFormatContext*)createAVFormatContextWithMovieID:(uint16_t)movieID error:(NSError**)error;
@end

@interface MHKArchive (MHKArchiveWAVAdditions)
- (NSDictionary*)soundDescriptorWithID:(uint16_t)soundID error:(NSError**)error;
- (MHKFileHandle*)openSoundWithID:(uint16_t)soundID error:(NSError**)error;
- (id<MHKAudioDecompression>)decompressorWithSoundID:(uint16_t)soundID error:(NSError**)error;
@end

@interface MHKArchive (MHKArchiveBitmapAdditions)
- (NSDictionary*)bitmapDescriptorWithID:(uint16_t)bitmapID error:(NSError**)error;
- (BOOL)loadBitmapWithID:(uint16_t)bitmapID buffer:(void*)pixels format:(MHK_BITMAP_FORMAT)format error:(NSError**)error;
@end
