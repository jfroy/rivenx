//
//	MHKMP2Decompressor.m
//	MHKKit
//
//	Created by Jean-Francois Roy on 07/06/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <stdlib.h>

#import <dlfcn.h>
#import <pthread.h>

#import <avcodec.h>

#import "MHKMP2Decompressor.h"
#import "MHKErrors.h"
#import "PHSErrorMacros.h"

#define BUFFER_OFFSET(buffer, bytes) ((uint8_t *)buffer + (bytes))

#define READ_BUFFER_SIZE 0x2000
#define MPEG_AUDIO_LAYER_2_FRAMES_PER_PACKET 1152
#define FRAME_SKIP_FUDGE 481


static BOOL MHKMP2Decompressor_libav_available = NO;
static pthread_mutex_t ffmpeg_mutex;

struct ffmpeg_state {
	void* avcodec_handle;
	void* avutil_handle;
	
	void (*avcodec_init)(void);
	void (*avcodec_register_all)(void);
	AVCodec *(*avcodec_find_decoder)(enum CodecID codecID);
	AVCodecContext *(*avcodec_alloc_context)(void);
	int (*avcodec_open)(AVCodecContext* avctx, AVCodec* codec);
	int (*avcodec_close)(AVCodecContext* avctx);
	int (*avcodec_decode_audio)(AVCodecContext* avctx, int16_t* samples, int* frame_size_ptr, uint8_t* buf, int buf_size);
	
	AVCodec* mp2_codec;
};

static struct ffmpeg_state _ffmpeg_state;

const uint32_t _mpeg_audio_nominal_sampling_rate_table[3] = {44100, 48000, 32000};
const uint32_t _mpeg_audio_v1_bitrates[3][14] = {
	{32000, 64000, 96000, 128000, 160000, 192000, 224000, 256000, 288000, 320000, 352000, 384000, 416000, 448000}, 
	{32000, 48000, 56000,  64000,  80000,  96000, 112000, 128000, 160000, 192000, 224000, 256000, 320000, 384000}, 
	{32000, 40000, 48000,  56000,  64000,  80000,  96000, 112000, 128000, 160000, 192000, 224000, 256000, 320000}
};
const uint32_t _mpeg_audio_v2_bitrates[3][14] = {
	{32000, 48000, 56000,  64000,  80000,  96000, 112000, 128000, 144000, 160000, 176000, 192000, 224000, 256000}, 
	{ 8000, 16000, 24000,  32000,  40000,  48000,  56000,  64000,  80000,  96000, 112000, 128000, 144000, 160000},
	{ 8000, 16000, 24000,  32000,  40000,  48000,  56000,  64000,  80000,  96000, 112000, 128000, 144000, 160000}
};
const uint32_t* const _mpeg_audio_bitrate_tables[2] = { 
	(const uint32_t *const)_mpeg_audio_v1_bitrates, 
	(const uint32_t *const)_mpeg_audio_v2_bitrates
};

static uint32_t _compute_mpeg_audio_frame_length(uint32_t header) {
	uint8_t bitrate_index = (header >> 12) & 0xf;
	if (bitrate_index == 0)
		return 0;
	bitrate_index--;
	
	uint8_t sampling_rate_index = (header >> 10) & 0x3;
	uint8_t padding_flag = (header >> 9) & 0x1;
	uint8_t layer_index = 3 - ((header >> 17) & 0x3);
	
	// note that under this logic, mpeg25 implies lsf, which is correct
	uint8_t mpeg_version = (header >> 19) & 0x3;
	uint8_t mpeg25_flag = (mpeg_version == 0) ? 1 : 0;
	uint8_t lsf_flag = (mpeg_version != 0x3) ? 1 : 0;
	
	// if we're mpeg25, we need to divide the nominal sampling rate by 4. if we're just lsf, divide by 2
	uint32_t sampling_rate = _mpeg_audio_nominal_sampling_rate_table[sampling_rate_index] >> (mpeg25_flag + lsf_flag);
	
	// bitrate
	uint32_t bitrate = *(_mpeg_audio_bitrate_tables[lsf_flag] + (layer_index * 14) + bitrate_index);
	
	// and finally, frame length
	uint32_t frame_length = 0;
	switch (layer_index) {
		case 0:
			frame_length = (((bitrate * 12) / sampling_rate) + padding_flag) * 4;
			break;
		case 1:
			frame_length = ((bitrate * 144) / sampling_rate) + padding_flag;
			break;
		case 2:
			// we need to multiply by 2 the sampling rate for lsf layer III MPEG streams
			sampling_rate <<= lsf_flag;
			frame_length = ((bitrate * 144) / sampling_rate) + padding_flag;
			break;
		default:
			frame_length = UINT32_MAX;
	}
	
	return frame_length;
}

static inline int _valid_id3_buffer_predicate(const uint8_t *id3_buffer) {
	return (id3_buffer[0] == 'I' && id3_buffer[1] == 'D' && id3_buffer[2] == '3' &&
			id3_buffer[3] != 0xff && id3_buffer[4] != 0xff &&
			(id3_buffer[6] & 0x80) == 0 &&
			(id3_buffer[7] & 0x80) == 0 &&
			(id3_buffer[8] & 0x80) == 0 &&
			(id3_buffer[9] & 0x80) == 0);
}

static inline int _valid_mpeg_audio_frame_header_predicate(uint32_t header) {
	// 11 sync bits
	if ((header & 0xffe00000) != 0xffe00000)
		return 0;
	
	// check that the audio layer is valid
	if ((header & (3 << 17)) == 0)
		return 0;
	
	// the bitrate index cannot be 0xf
	if ((header & (0xf << 12)) == 0xf << 12)
		return 0;
	
	// sampling rate cannot be 0x3
	if ((header & (3 << 10)) == 3 << 10)
		return 0;
	
	// we check out
	return 1;
}


@implementation MHKMP2Decompressor

+ (void)loadFFMPEG {
#if defined(DEBUG) && DEBUG > 2
	NSLog(@"initializing FFmpeg...");
#endif
	
	// load the function pointers we need
	_ffmpeg_state.avcodec_init = dlsym(_ffmpeg_state.avcodec_handle, "avcodec_init");
	_ffmpeg_state.avcodec_register_all = dlsym(_ffmpeg_state.avcodec_handle, "avcodec_register_all");
	_ffmpeg_state.avcodec_find_decoder = dlsym(_ffmpeg_state.avcodec_handle, "avcodec_find_decoder");
	_ffmpeg_state.avcodec_alloc_context = dlsym(_ffmpeg_state.avcodec_handle, "avcodec_alloc_context");
	_ffmpeg_state.avcodec_open = dlsym(_ffmpeg_state.avcodec_handle, "avcodec_open");
	_ffmpeg_state.avcodec_close = dlsym(_ffmpeg_state.avcodec_handle, "avcodec_close");
	_ffmpeg_state.avcodec_decode_audio = dlsym(_ffmpeg_state.avcodec_handle, "avcodec_decode_audio");
	
	// initialize libavcodec and the MPEG 1/2 audio layer decoder
	_ffmpeg_state.avcodec_init();
	_ffmpeg_state.avcodec_register_all();
	_ffmpeg_state.mp2_codec = _ffmpeg_state.avcodec_find_decoder(CODEC_ID_MP2);
	
	// FFmpeg mutex
	pthread_mutex_init(&ffmpeg_mutex, NULL);
}

+ (void)initialize {
	static BOOL MHKMP2Decompressor_has_initialized = NO;
	if (!MHKMP2Decompressor_has_initialized) {
		MHKMP2Decompressor_has_initialized = YES;
		
		// get a bundle to MHKKit and the path to the Resources directory
		NSBundle* mhk_bundle = [NSBundle bundleForClass:[self class]];
		NSString* resource_path = [mhk_bundle resourcePath];
		char* error_string = NULL;
		
		// load libavutil
		_ffmpeg_state.avutil_handle = dlopen([[resource_path stringByAppendingPathComponent:@"libavutil.dylib"] fileSystemRepresentation], RTLD_LAZY | RTLD_GLOBAL);
		error_string = dlerror();
		if (error_string)
			printf("%s\n", error_string);
		
		// load libavcodec
		_ffmpeg_state.avcodec_handle = dlopen([[resource_path stringByAppendingPathComponent:@"libavcodec.dylib"] fileSystemRepresentation], RTLD_LAZY | RTLD_GLOBAL);
		error_string = dlerror();
		if (error_string)
			fprintf(stderr, "%s\n", error_string);
		
		// load ffmpeg if we were able to link libavcodec
		if (_ffmpeg_state.avcodec_handle) {
			MHKMP2Decompressor_libav_available = YES;
			[self loadFFMPEG];
		}
	}
}

- (void)_build_packet_description_table_and_count_frames:(NSError**)errorPtr {
	UInt8* read_buffer = malloc(READ_BUFFER_SIZE);
	ssize_t size_left_in_buffer = 0;
	UInt32 buffer_position = 0;
	
	const SInt64 source_length = [_data_source length];
	SInt64 source_position = [_data_source offsetInFile];
	
	// initialize the packet count
	_packet_count = 0;
	
	// start with say 3000 packets
	size_t packet_table_length = 3000;
	_packet_table = calloc(packet_table_length, sizeof(AudioStreamPacketDescription));
	if (!_packet_table) {
		free(read_buffer);
		ReturnWithError(NSPOSIXErrorDomain, errno, nil, errorPtr)
	}
	
	// loop while we still have data left to process
	while (source_position < source_length) {
		// is the read buffer empty?
		if (size_left_in_buffer == 0) {
			size_left_in_buffer = [_data_source readDataOfLength:READ_BUFFER_SIZE inBuffer:read_buffer error:errorPtr];
			if (size_left_in_buffer == -1) {
				free(read_buffer);
				return;
			}
			
			if (size_left_in_buffer == 0 && [*errorPtr code] == eofErr)
				break;
			
			source_position = [_data_source offsetInFile];
			buffer_position = 0;
		}
		
		// find the next frame sync
		while (size_left_in_buffer >= 4) {
			uint32_t mpeg_header = CFSwapInt32BigToHost(*(uint32_t *)read_buffer);
			if (_valid_mpeg_audio_frame_header_predicate(mpeg_header)) {
				// compute the frame length to seek to the next frame
				UInt32 frame_length = _compute_mpeg_audio_frame_length(mpeg_header);
				
				// do we need a bigger packet table?
				if (packet_table_length < _packet_count) {
					packet_table_length *= 2;
					_packet_table = reallocf(_packet_table, packet_table_length * sizeof(AudioStreamPacketDescription));
					if (!_packet_table) {
						free(read_buffer);
						ReturnWithError(NSPOSIXErrorDomain, errno, nil, errorPtr)
					}
				}
				
				// load up the packet description entry
				_packet_table[_packet_count].mStartOffset = source_position - size_left_in_buffer;
				_packet_table[_packet_count].mDataByteSize = frame_length;
				_packet_table[_packet_count].mVariableFramesInPacket = 0;
				
				// one packet for the team
				_packet_count++;
				
				// update the maximum packet size
				if (frame_length > _max_packet_size)
					_max_packet_size = frame_length;
				
				// if the whole frame isn't in the buffer, fill it up
				if (size_left_in_buffer < frame_length) {
					memmove(read_buffer, read_buffer + buffer_position, size_left_in_buffer);
			
					size_left_in_buffer += [_data_source readDataOfLength:(READ_BUFFER_SIZE - size_left_in_buffer) inBuffer:(read_buffer + size_left_in_buffer) error:errorPtr];
					if (size_left_in_buffer == -1) {
						free(read_buffer);
						return;
					}
					
					if (size_left_in_buffer == 0 && [*errorPtr code] == eofErr)
						break;
			
					source_position = [_data_source offsetInFile];
					buffer_position = 0;
				}
				
				buffer_position += frame_length;
				size_left_in_buffer -= frame_length;
			} else {
				buffer_position++;
				size_left_in_buffer--;
			}
		}
		
		// if we have 3 or less but not 0 bytes left in the buffer, move them up front and read some more bytes
		if (size_left_in_buffer < 4 && size_left_in_buffer > 0) {
			memmove(read_buffer, read_buffer + buffer_position, size_left_in_buffer);
			
			size_left_in_buffer += [_data_source readDataOfLength:(READ_BUFFER_SIZE - size_left_in_buffer) inBuffer:(read_buffer + size_left_in_buffer) error:errorPtr];
			if (size_left_in_buffer == -1) {
				free(read_buffer);
				return;
			}
			
			if (size_left_in_buffer == 0 && [*errorPtr code] == eofErr)
				break;
			
			source_position = [_data_source offsetInFile];
			buffer_position = 0;
		}
	}
	
	free(read_buffer);
}

- (id)init {
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (id)initWithChannelCount:(UInt32)channels frameCount:(SInt64)frames samplingRate:(double)sps fileHandle:(MHKFileHandle *)fh error:(NSError **)errorPtr {
	self = [super init];
	if (!self) return nil;
	
	// we can't do anything without ffmpeg
	if (!MHKMP2Decompressor_libav_available)
		ReturnFromInitWithError(MHKErrorDomain, errFFMPEGNotAvailable, nil, errorPtr)
	
	// MPEG 2 audio can only store 1 or 2 channels
	if (channels != 1 && channels != 2)
		ReturnFromInitWithError(MHKErrorDomain, errInvalidChannelCount, nil, errorPtr)
	
	_channel_count = channels;
	_frame_count = frames;
	_data_source = [fh retain];
	
	// setup the output ABSD
	_output_absd.mFormatID = kAudioFormatLinearPCM;
	_output_absd.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
	_output_absd.mSampleRate = sps;
	_output_absd.mChannelsPerFrame = _channel_count;
	_output_absd.mBitsPerChannel = 32;
	_output_absd.mFramesPerPacket = 1;
	_output_absd.mBytesPerFrame = _output_absd.mChannelsPerFrame * _output_absd.mBitsPerChannel / 8;
	_output_absd.mBytesPerPacket = _output_absd.mFramesPerPacket * _output_absd.mBytesPerFrame;
	
	// setup the decompression ABSD
	_decomp_absd.mFormatID = kAudioFormatLinearPCM;
	_decomp_absd.mFormatFlags = kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	_decomp_absd.mSampleRate = sps;
	_decomp_absd.mChannelsPerFrame = _channel_count;
	_decomp_absd.mBitsPerChannel = 16;
	_decomp_absd.mFramesPerPacket = 1;
	_decomp_absd.mBytesPerFrame = _decomp_absd.mChannelsPerFrame * _decomp_absd.mBitsPerChannel / 8;
	_decomp_absd.mBytesPerPacket = _decomp_absd.mFramesPerPacket * _decomp_absd.mBytesPerFrame;
	
	// using the input and output absds, setup an AudioConverter
	OSStatus err = AudioConverterNew(&_decomp_absd, &_output_absd, &_converter);
	if (err)
		ReturnFromInitWithError(NSOSStatusErrorDomain, err, nil, errorPtr)
	
	// allocate the codec context
	pthread_mutex_lock(&ffmpeg_mutex);
	_mp2_codec_context = _ffmpeg_state.avcodec_alloc_context();
	if (!_mp2_codec_context) {
		pthread_mutex_unlock(&ffmpeg_mutex);
		ReturnFromInitWithError(NSPOSIXErrorDomain, errno, nil, errorPtr)
	}
	
	// open the codec
	int result = _ffmpeg_state.avcodec_open((AVCodecContext*)_mp2_codec_context, _ffmpeg_state.mp2_codec);
	pthread_mutex_unlock(&ffmpeg_mutex);
	if (result < 0)
		ReturnFromInitWithError(MHKffmpegErrorDomain, result, nil, errorPtr)
	
	NSError* local_error = nil;
	
	// read 10 bytes to check for ID3 meta-data
	UInt8 id3_buffer[10];
	[_data_source seekToFileOffset:0];
	ssize_t bytes_read = [_data_source readDataOfLength:10 inBuffer:id3_buffer error:&local_error];
	if (bytes_read != 10) {
		if (errorPtr)
			*errorPtr = local_error;
		[self release];
		return nil;
	}
	
	// if we have a valid ID3 chunk, determine its length
	if (_valid_id3_buffer_predicate(id3_buffer)) {
		SInt64 id3_length = ((id3_buffer[6] & 0x7f) << 21) | ((id3_buffer[7] & 0x7f) << 14) | ((id3_buffer[8] & 0x7f) << 7) | (id3_buffer[9] & 0x7f);
		if (id3_buffer[5] & 0x10)
			id3_length += 10;
		
		_audio_packets_start_offset = 10 + id3_length;
	} else {
		_audio_packets_start_offset = 0;
	}
	
	// seek to the first audio data packet
	[_data_source seekToFileOffset:_audio_packets_start_offset];
	
	// build the packet description table
	_max_packet_size = 0;
	[self _build_packet_description_table_and_count_frames:&local_error];
	if (local_error) {
		if (errorPtr)
			*errorPtr = local_error;
		[self release];
		return nil;
	}
	
	// compute the integer (audio) frame count (layer II always uses 1152 audio frames per MPEG frames)
	SInt64 integer_frame_count = _packet_count * MPEG_AUDIO_LAYER_2_FRAMES_PER_PACKET;
	
	// if we're told we have more frames than we can have, bail
	if (_frame_count > integer_frame_count) ReturnFromInitWithError(MHKErrorDomain, errInvalidFrameCount, nil, errorPtr)
	
	// compute how many bytes we should drop from the first packet (where extra silence will be)
	_bytes_to_drop = FRAME_SKIP_FUDGE * _decomp_absd.mBytesPerFrame;
	
	// allocate the decompression buffer
	_decompression_buffer_length = MPEG_AUDIO_LAYER_2_FRAMES_PER_PACKET * sizeof(SInt16) * _channel_count;
	_decompression_buffer = malloc(_decompression_buffer_length);
	if (!_decompression_buffer)
		ReturnFromInitWithError(NSPOSIXErrorDomain, errno, nil, errorPtr)
	
	// allocate the packet buffer
	_packet_buffer = malloc(_max_packet_size * 50);
	if (!_packet_buffer)
		ReturnFromInitWithError(NSPOSIXErrorDomain, errno, nil, errorPtr)
	
	// create the decompressor lock
	pthread_mutex_init(&_decompressor_lock, NULL);
	
	// initialize the decompressor
	[self reset];
	
	return self;
}

- (void)dealloc {
	// close the decoder
	pthread_mutex_lock(&ffmpeg_mutex);
	if (_mp2_codec_context) _ffmpeg_state.avcodec_close((AVCodecContext*)_mp2_codec_context);
	pthread_mutex_unlock(&ffmpeg_mutex);
	
	// close the converter
	if (_converter) AudioConverterDispose(_converter);
	
	// free memory resources
	if (_packet_buffer) free(_packet_buffer);
	if (_decompression_buffer) free(_decompression_buffer);
	if (_mp2_codec_context) free(_mp2_codec_context);
	if (_packet_table) free(_packet_table);
	
	[_data_source release];
	
	pthread_mutex_destroy(&_decompressor_lock);
	
	[super dealloc];
}

- (AudioStreamBasicDescription)outputFormat {
	return _output_absd;
}

- (SInt64)frameCount {
	return _frame_count;
}

- (void)reset {
	pthread_mutex_lock(&_decompressor_lock);
	
	// seek to the first audio data packet
	[_data_source seekToFileOffset:_audio_packets_start_offset];
	
	// reset the decompression buffer
	_decompression_buffer_position = 0;
	
	// start at the first packet, no packets available initially, current packet set to the read buffer's head
	_packet_index = 0;
	_available_packets = 0;
	_current_packet = _packet_buffer;
	
	// reset the audio converter
	AudioConverterReset(_converter);
	
	// close and re-open the codec context
	pthread_mutex_lock(&ffmpeg_mutex);
	if (_mp2_codec_context)
		_ffmpeg_state.avcodec_close((AVCodecContext*)_mp2_codec_context);
	_mp2_codec_context = _ffmpeg_state.avcodec_alloc_context();
	_ffmpeg_state.avcodec_open((AVCodecContext*)_mp2_codec_context, _ffmpeg_state.mp2_codec);
	pthread_mutex_unlock(&ffmpeg_mutex);
	
	pthread_mutex_unlock(&_decompressor_lock);
}

- (void)fillAudioBufferList:(AudioBufferList *)abl {
	pthread_mutex_lock(&_decompressor_lock);
	
	OSStatus err = noErr;
	
	// from the provided buffer length, compute how many frames we need to decompress
	UInt32 bytes_to_decompress = abl->mBuffers[0].mDataByteSize;
	UInt32 decompressed_bytes = 0;
	
	// to be used with the converter
	UInt32 converted_bytes = 0;
	
	// if we have frames left from the last fill, load them up
	if (_decompression_buffer_position > 0) {
		// compute how many bytes we need to convert
		converted_bytes = ((_decompression_buffer_length - _decompression_buffer_position) / _decomp_absd.mBytesPerFrame) * _output_absd.mBytesPerFrame;
		if (converted_bytes > bytes_to_decompress)
			converted_bytes = bytes_to_decompress;
		
		// convert the bytes
		err = AudioConverterConvertBuffer(_converter, 
										  (converted_bytes / _output_absd.mBytesPerFrame) * _decomp_absd.mBytesPerFrame, 
										  BUFFER_OFFSET(_decompression_buffer, _decompression_buffer_position), 
										  &converted_bytes, 
										  BUFFER_OFFSET(abl->mBuffers[0].mData, decompressed_bytes));
		if (err) goto AbortFill;
		
		// update decompression state
		decompressed_bytes += converted_bytes;
		bytes_to_decompress -= converted_bytes;
		
		// update the decompression buffer state
		_decompression_buffer_position += (converted_bytes / _output_absd.mBytesPerFrame) * _decomp_absd.mBytesPerFrame;
		if (_decompression_buffer_position == _decompression_buffer_length)
			_decompression_buffer_position = 0;
	}
	
	// did we already process every available packet?
	if (_packet_index == _packet_count)
		goto AbortFill;
	
	// compute how many packets we'll need to process
	UInt32 packets_to_decompress = (bytes_to_decompress / _output_absd.mBytesPerFrame) / MPEG_AUDIO_LAYER_2_FRAMES_PER_PACKET;
	if ((bytes_to_decompress / _output_absd.mBytesPerFrame) % MPEG_AUDIO_LAYER_2_FRAMES_PER_PACKET)
		packets_to_decompress++;
	
	// explicit cast OK here, can't really have more than 4 billion packets to decompress...
	if (packets_to_decompress > (UInt32)(_packet_count - _packet_index))
		packets_to_decompress = (UInt32)(_packet_count - _packet_index);
	
	while (packets_to_decompress > 0) {
		// if we ran out of packets in memory, read some more
		if (_available_packets == 0) {
			// did we process every available packet?
			if (_packet_index == _packet_count)
				goto AbortFill;
			
			// compute the length of an integral number of packets that we can read, up to 50 packets
			UInt32 bytes_to_read = _max_packet_size * 50;
			if (bytes_to_read > [_data_source length] - [_data_source offsetInFile]) {
				// explicit cast OK here, API limited to 32-bit read sizes
				bytes_to_read = (UInt32)((([_data_source length] - [_data_source offsetInFile]) / _max_packet_size) * _max_packet_size);
			}
			
			// read the packets
			ssize_t bytes_read = [_data_source readDataOfLength:bytes_to_read inBuffer:_packet_buffer error:nil];
			if (bytes_read != bytes_to_read)
				goto AbortFill;
			
			// reset the packet buffer state
			_available_packets = bytes_read / _max_packet_size;
			_current_packet = _packet_buffer;
		}
		
		// decompress a packet
		int libavcodec_frame_size = _decompression_buffer_length;
		_ffmpeg_state.avcodec_decode_audio((AVCodecContext*)_mp2_codec_context, _decompression_buffer, &libavcodec_frame_size, _current_packet, _packet_table[_packet_index].mDataByteSize);
		if (libavcodec_frame_size == 0)
			goto AbortFill;
		
		// apply the byte skip
		if (_packet_index == 0) {
			// temporarily advance the decompression buffer and update libavcodec_frame_size to match
			_decompression_buffer = BUFFER_OFFSET(_decompression_buffer, _bytes_to_drop);
			libavcodec_frame_size -= _bytes_to_drop;
		}
		
		// compute how many bytes we need to convert
		converted_bytes = (libavcodec_frame_size / _decomp_absd.mBytesPerFrame) * _output_absd.mBytesPerFrame;
		if (converted_bytes > bytes_to_decompress) {
			converted_bytes = bytes_to_decompress;
			libavcodec_frame_size = (converted_bytes / _output_absd.mBytesPerFrame) * _decomp_absd.mBytesPerFrame;
		}
		
		// convert the bytes
		err = AudioConverterConvertBuffer(_converter, 
										  libavcodec_frame_size, 
										  _decompression_buffer, 
										  &converted_bytes, 
										  BUFFER_OFFSET(abl->mBuffers[0].mData, decompressed_bytes));
		
		// undo the byte skip
		if (_packet_index == 0)
			_decompression_buffer = BUFFER_OFFSET(_decompression_buffer, -_bytes_to_drop);
		
		// handle a possible converter error
		if (err)
			goto AbortFill;
		
		// update decompression state
		decompressed_bytes += converted_bytes;
		bytes_to_decompress -= converted_bytes;
		
		// we might need to dynamically tack on an extra packet if we dropped bytes from the first packet
		if (_packet_index == 0 && _packet_index < _packet_count && packets_to_decompress == 1 && bytes_to_decompress > 0)
			packets_to_decompress++;
		
		// one less packet to go
		packets_to_decompress--;
		_current_packet = BUFFER_OFFSET(_current_packet, _packet_table[_packet_index].mDataByteSize);
		_available_packets--;
		_packet_index++;
	}
	
	// update the decompression buffer state
	_decompression_buffer_position += (converted_bytes / _output_absd.mBytesPerFrame) * _decomp_absd.mBytesPerFrame;
	if (_decompression_buffer_position == _decompression_buffer_length)
		_decompression_buffer_position = 0;
		
AbortFill:
	// recompute frames_to_decompress and zero undecompressed samples
	bytes_to_decompress = abl->mBuffers[0].mDataByteSize;
	
	if (decompressed_bytes < bytes_to_decompress)
		bzero(BUFFER_OFFSET(abl->mBuffers[0].mData, decompressed_bytes), bytes_to_decompress - decompressed_bytes);

	pthread_mutex_unlock(&_decompressor_lock);
}

@end
