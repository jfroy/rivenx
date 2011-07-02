//
//  MHKADPCMDecompressor.m
//  MHKKit
//
//  Created by Jean-Francois Roy on 06/24/2005.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "mohawk_core.h"
#import "MHKADPCMDecompressor.h"
#import "MHKErrors.h"


#define READ_BUFFER_SIZE 0x8000

static const int16_t g_adpcm_index_deltas[16] = {
    -1,-1,-1,-1, 2, 4, 6, 8,
    -1,-1,-1,-1, 2, 4, 6, 8
};

/*  DVI ADPCM step table */
static const int16_t g_adpcm_step_sizes[89] = {
    7,     8,     9,     10,    11,    12,    13,    14,    16,     17,    19,
    21,    23,    25,    28,    31,    34,    37,    41,    45,     50,    55,
    60,    66,    73,    80,    88,    97,    107,   118,   130,    143,   157,
    173,   190,   209,   230,   253,   279,   307,   337,   371,    408,   449,
    494,   544,   598,   658,   724,   796,   876,   963,   1060,   1166,  1282,
    1411,  1552,  1707,  1878,  2066,  2272,  2499,  2749,  3024,   3327,  3660,
    4026,  4428,  4871,  5358,  5894,  6484,  7132,  7845,  8630,   9493,  10442,
    11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623,  27086, 29794,
    32767
};


MHK_INLINE int32_t _MHK_adpcm_decode_delta(int32_t stepSize, char encodedSample) {
    int32_t delta = 0;
    
    if (encodedSample & 0x4)
        delta = stepSize;
    
    if (encodedSample & 0x2)
        delta += (stepSize >> 0x1);
    
    if (encodedSample & 0x1)
        delta += (stepSize >> 0x2);
    
    delta += (stepSize >> 0x3);
    if (encodedSample & 0x8)
        delta = -delta;
    
    return delta;
}

MHK_INLINE float _MHK_sample_convert_to_float(int32_t sample) {
    if (sample >= 0)
        return sample / 32767.0F;
    else
        return sample / 32768.0F;
}


@implementation MHKADPCMDecompressor

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithChannelCount:(UInt32)channels frameCount:(SInt64)frames samplingRate:(double)sps fileHandle:(MHKFileHandle*)fh error:(NSError**)errorPtr {
    self = [super init];
    if (!self) return nil;
    
    // ADPCM only works for 1 or 2 channels
    if (channels != 1 && channels != 2)
        ReturnFromInitWithError(MHKErrorDomain, errInvalidChannelCount, nil, errorPtr);
        
    channel_count = channels;
    data_source = [fh retain];
    data_source_init_offset = [fh offsetInFile];
    
    // setup the output ABSD
    output_absd.mFormatID = kAudioFormatLinearPCM;
    output_absd.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    output_absd.mSampleRate = sps;
    output_absd.mChannelsPerFrame = channel_count;
    output_absd.mBitsPerChannel = 32;
    output_absd.mFramesPerPacket = 1;
    output_absd.mBytesPerFrame = output_absd.mChannelsPerFrame * output_absd.mBitsPerChannel / 8;
    output_absd.mBytesPerPacket = output_absd.mFramesPerPacket * output_absd.mBytesPerFrame;
    
    frame_count = frames;
    adpcm_buffer = malloc(READ_BUFFER_SIZE);
    
    [self reset];
    
    return self;
}

- (void)dealloc {
    [data_source release];
    free(adpcm_buffer);
    
    [super dealloc];
}

- (AudioStreamBasicDescription)outputFormat {
    return output_absd;
}

- (SInt64)frameCount {
    return frame_count;
}

- (void)reset {
#if defined(DEBUG) && DEBUG > 1
    NSLog(@"%@: resetting", self);
#endif
    estimate_left = 0;
    estimate_right = 0;
    
    step_index_left = 0;
    step_index_right = 0;
    
    step_size_left = g_adpcm_step_sizes[step_index_left];
    step_size_right = g_adpcm_step_sizes[step_index_right];
    
    [data_source seekToFileOffset:data_source_init_offset];
}

- (void)fillAudioBufferList:(AudioBufferList*)abl { 
    // from the provided buffer length, compute how many bytes from the compressed bitsream we'll need
    uint32_t frames_to_decompress = abl->mBuffers[0].mDataByteSize / output_absd.mBytesPerFrame;
    
    // compute the bitstream length (how much data we need to read)
    uint32_t bitstream_length = frames_to_decompress;
    if (channel_count == 1) {
        bitstream_length /= 2;
        if (frames_to_decompress % 2)
            bitstream_length++;
    }
    
    if (bitstream_length > READ_BUFFER_SIZE)
        bitstream_length = READ_BUFFER_SIZE;
    
    // setup the pointers so we don't have branches in our decompression loop
    int32_t* estimate_1 = &estimate_left;
    int32_t* step_index_1 = &step_index_left;
    int32_t* step_size_1 = &step_size_left;
    
    int32_t* estimate_2 = NULL;
    int32_t* step_index_2 = NULL;
    int32_t* step_size_2 = NULL;
    
    if (channel_count == 2) {
        estimate_2 = &estimate_right;
        step_index_2 = &step_index_right;
        step_size_2 = &step_size_right;
    } else {
        estimate_2 = &estimate_left;
        step_index_2 = &step_index_left;
        step_size_2 = &step_size_left;
    }
    
    // cache the audio buffer as a float pointer
    float* output_buffer = (float*)abl->mBuffers[0].mData;
    
    // cache the input buffer
    uint8_t* local_adpcm_buffer = adpcm_buffer;
    
    // ask the data source to read the compressed samples, and recompute frames_to_decompress
    int32_t read_length = (int32_t)[data_source readDataOfLength:bitstream_length inBuffer:adpcm_buffer error:nil];
    
    // we need an external read loop because of the fixed size read buffer
    uint32_t decompressed_frames = 0;
    uint32_t frames_per_cycle = 2 / channel_count;
    while (read_length > 0 && decompressed_frames < frames_to_decompress) {
        // compute how many frames we'll decompress this particular cycle
        uint32_t frames_to_decompress_this_cycle = (2 / channel_count) * read_length;
        
        // decompression loop
        for (uint32_t frame_index = 0; frame_index < frames_to_decompress_this_cycle; frame_index += frames_per_cycle) {
            // first sample
            uint8_t compressed_sample = (*local_adpcm_buffer & 0xF0) >> 4;
            int32_t sample = *estimate_1;
            int32_t step_index = *step_index_1;
            
            // decode ADPCM code value to reproduce Dn and accumulates an estimated output sample
            sample += _MHK_adpcm_decode_delta(*step_size_1, compressed_sample);
            
            // clip the sample to the int16_t range
            sample = (sample >= -32768L) ? sample : -32768L;
            sample = (sample <= 32767L) ? sample : 32767L;
            
            // update the last estimated sample and output final float sample to buffer
            *estimate_1 = sample;
            *output_buffer = _MHK_sample_convert_to_float(sample);
            output_buffer++;
            
            // stepsize adaptation for next sample
            step_index += g_adpcm_index_deltas[compressed_sample];
            step_index = (step_index >= 0) ? step_index : 0;
            step_index = (step_index <= 88) ? step_index : 88;
            *step_size_1 = g_adpcm_step_sizes[step_index];
            *step_index_1 = step_index;
            
            // second sample
            compressed_sample = *local_adpcm_buffer & 0x0F;
            sample = *estimate_2;
            step_index = *step_index_2;
            
            // decode ADPCM code value to reproduce Dn and accumulates an estimated output sample
            sample += _MHK_adpcm_decode_delta(*step_size_2, compressed_sample);
            
            // clip the sample to the int16_t range
            sample = (sample >= -32768L) ? sample : -32768L;
            sample = (sample <= 32767L) ? sample : 32767L;
            
            // update the last estimated sample and output final float sample to buffer
            *estimate_2 = sample;
            *output_buffer = _MHK_sample_convert_to_float(sample);
            output_buffer++;
            
            // stepsize adaptation for next sample
            step_index += g_adpcm_index_deltas[compressed_sample];
            step_index = (step_index >= 0) ? step_index : 0;
            step_index = (step_index <= 88) ? step_index : 88;
            *step_size_2 = g_adpcm_step_sizes[step_index];
            *step_index_2 = step_index;
            
            // increment the local adpcm buffer
            local_adpcm_buffer++;
        }
        
        // update the number of decompressed frames
        decompressed_frames += frames_to_decompress_this_cycle;
        
        // are we done?
        if (decompressed_frames == frames_to_decompress)
            break;
        
        // we're not done. compute how much more data we need to read
        bitstream_length = frames_to_decompress - decompressed_frames;
        if (channel_count == 1) {
            bitstream_length /= 2;
            if ((frames_to_decompress - decompressed_frames) % 2)
                bitstream_length++;
        }
        
        if (bitstream_length > READ_BUFFER_SIZE)
            bitstream_length = READ_BUFFER_SIZE;
        
        // read some more data
        read_length = (int32_t)[data_source readDataOfLength:bitstream_length inBuffer:adpcm_buffer error:nil];
        
        // reset the local adpcm buffer pointer
        local_adpcm_buffer = adpcm_buffer;
    }
    
    // zero un-decoded space
    if (decompressed_frames < frames_to_decompress)
        bzero(output_buffer, (frames_to_decompress - decompressed_frames) * output_absd.mBytesPerFrame);
}

@end
