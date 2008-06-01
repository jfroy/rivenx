//
//	MHKMP2Decompressor.h
//	MHKKit
//
//	Created by Jean-Francois Roy on 07/06/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import "MHKAudioDecompression.h"
#import "MHKFileHandle.h"

#import <CoreAudio/CoreAudioTypes.h>
#import <AudioToolbox/AudioConverter.h>

#import <avcodec.h>


@interface MHKMP2Decompressor : NSObject <MHKAudioDecompression> {
	MHKFileHandle *__data_source;
	
	UInt32 __channel_count;
	AudioStreamBasicDescription __output_absd;
	AudioStreamBasicDescription __decomp_absd;
	
	SInt64 __audio_packets_start_offset;
	SInt64 __packet_count;
	UInt32 __max_packet_size;
	AudioStreamPacketDescription *__packet_table;
	
	SInt64 __frame_count;
	UInt32 __bytes_to_drop;
	
	SInt64 __packet_index;
	UInt32 __available_packets;
	void *__packet_buffer;
	void *__current_packet;
	
	UInt32 __decompression_buffer_position;
	UInt32 __decompression_buffer_length;
	void *__decompression_buffer;
	
	// CoreAudio stuff
	AudioConverterRef __converter;
	
	// ffmpeg stuff
	AVCodecContext *__mp2_codec_context;
}

- (id)initWithChannelCount:(UInt32)channels frameCount:(SInt64)frames samplingRate:(double)sps fileHandle:(MHKFileHandle *)fh error:(NSError **)errorPtr;

@end
