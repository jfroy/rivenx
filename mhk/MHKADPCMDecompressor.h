//
//  MHKADPCMDecompressor.h
//  MHKKit
//
//  Created by Jean-Francois Roy on 06/24/2005.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "MHKAudioDecompression.h"
#import "MHKFileHandle.h"


@interface MHKADPCMDecompressor : NSObject <MHKAudioDecompression> {
    MHKFileHandle *data_source;
    SInt64 data_source_init_offset;
    
    int32_t channel_count;
    AudioStreamBasicDescription output_asbd;
    SInt64 frame_count;
    
    int32_t estimate_left; 
    int32_t estimate_right;
    
    int32_t step_size_left;
    int32_t step_size_right;
    
    int32_t step_index_left;
    int32_t step_index_right;
    
    uint8_t* adpcm_buffer;
}

- (id)initWithChannelCount:(UInt32)channels frameCount:(SInt64)frames samplingRate:(double)sps fileHandle:(MHKFileHandle*)fh error:(NSError**)errorPtr;

@end
