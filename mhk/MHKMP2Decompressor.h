//
//  MHKMP2Decompressor.h
//  MHKKit
//
//  Created by Jean-Francois Roy on 07/06/2005.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "MHKAudioDecompression.h"
#import "MHKFileHandle.h"

#import <CoreAudio/CoreAudioTypes.h>
#import <AudioToolbox/AudioConverter.h>

struct AVCodecContext;
struct AVFrame;

@interface MHKMP2Decompressor : NSObject <MHKAudioDecompression> {
    MHKFileHandle* _data_source;
    
    UInt32 _channel_count;
    AudioStreamBasicDescription _decomp_asbd;
    
    SInt64 _audio_packets_start_offset;
    SInt64 _packet_count;
    UInt32 _max_packet_size;
    AudioStreamPacketDescription* _packet_table;
    
    SInt64 _frame_count;
    UInt32 _bytes_to_drop;
    
    SInt64 _packet_index;
    size_t _available_packets;
    void* _packet_buffer;
    void* _current_packet;
    
    UInt32 _decompression_buffer_position;
    UInt32 _decompression_buffer_available;
    UInt32 _decompression_buffer_length;
    void* _decompression_buffer;
    
    struct AVCodecContext* _mp2_codec_context;
    struct AVFrame* _mp2_frame;
    
    pthread_mutex_t _decompressor_lock;
}

- (id)initWithChannelCount:(UInt32)channels frameCount:(SInt64)frames samplingRate:(double)sps fileHandle:(MHKFileHandle*)fh error:(NSError**)errorPtr;

@end
