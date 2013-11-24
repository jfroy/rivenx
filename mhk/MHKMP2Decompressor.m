//
//  MHKMP2Decompressor.m
//  MHKKit
//
//  Created by Jean-Francois Roy on 07/06/2005.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import <stdlib.h>
#import <dlfcn.h>
#import <pthread.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSPathUtilities.h>
#import <CoreServices/CoreServices.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#pragma clang diagnostic ignored "-Wduplicate-enum"
#import <libavcodec/avcodec.h>
#pragma clang diagnostic pop

#import "MHKMP2Decompressor.h"
#import "MHKErrors.h"
#import "Base/RXErrorMacros.h"

#define READ_BUFFER_SIZE 0x2000
#define MPEG_AUDIO_LAYER_2_FRAMES_PER_PACKET 1152
#define FRAME_SKIP_FUDGE 481

static BOOL MHKMP2Decompressor_libav_available = NO;
static pthread_mutex_t s_libav_mutex;

struct libav_state {
  void* avcodec_handle;

  void (*avcodec_register_all)(void);
  void (*av_freep)(void*);
  AVCodec* (*avcodec_find_decoder)(enum AVCodecID);
  AVCodecContext* (*avcodec_alloc_context3)(const AVCodec*);
  int (*avcodec_open2)(AVCodecContext*, const AVCodec*, AVDictionary**);
  int (*avcodec_close)(AVCodecContext*);
  AVFrame* (*avcodec_alloc_frame)(void);
  void (*avcodec_free_frame)(AVFrame**);
  int (*avcodec_decode_audio4)(AVCodecContext*, AVFrame*, int*, AVPacket*);

  AVCodec* mp2_codec;
};

static struct libav_state _libav_state;

static const uint32_t _mpeg_audio_nominal_sampling_rate_table[3] = {44100, 48000, 32000};
static const uint32_t _mpeg_audio_v1_bitrates[3][14] = {
    {32000, 64000, 96000, 128000, 160000, 192000, 224000, 256000, 288000, 320000, 352000, 384000, 416000, 448000}, 
    {32000, 48000, 56000,  64000,  80000,  96000, 112000, 128000, 160000, 192000, 224000, 256000, 320000, 384000}, 
    {32000, 40000, 48000,  56000,  64000,  80000,  96000, 112000, 128000, 160000, 192000, 224000, 256000, 320000}
};
static const uint32_t _mpeg_audio_v2_bitrates[3][14] = {
    {32000, 48000, 56000,  64000,  80000,  96000, 112000, 128000, 144000, 160000, 176000, 192000, 224000, 256000}, 
    { 8000, 16000, 24000,  32000,  40000,  48000,  56000,  64000,  80000,  96000, 112000, 128000, 144000, 160000},
    { 8000, 16000, 24000,  32000,  40000,  48000,  56000,  64000,  80000,  96000, 112000, 128000, 144000, 160000}
};
static const uint32_t* const _mpeg_audio_bitrate_tables[2] = { 
    (const uint32_t *const)_mpeg_audio_v1_bitrates, 
    (const uint32_t *const)_mpeg_audio_v2_bitrates
};

static uint32_t _compute_mpeg_audio_frame_length(uint32_t header)
{
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

static inline int _valid_id3_buffer_predicate(const uint8_t* id3_buffer)
{
  return (id3_buffer[0] == 'I' && id3_buffer[1] == 'D' && id3_buffer[2] == '3' && id3_buffer[3] != 0xff && id3_buffer[4] != 0xff &&
          (id3_buffer[6] & 0x80) == 0 && (id3_buffer[7] & 0x80) == 0 && (id3_buffer[8] & 0x80) == 0 && (id3_buffer[9] & 0x80) == 0);
}

static inline int _valid_mpeg_audio_frame_header_predicate(uint32_t header)
{
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

static int MHKMP2Decompressor_get_buffer(struct AVCodecContext* c, AVFrame* pic)
{
  MHKMP2Decompressor* decompressor = c->opaque;
  pic->data[0] = decompressor->_decompression_buffer;
  pic->extended_data[0] = decompressor->_decompression_buffer;
  pic->linesize[0] = pic->nb_samples * decompressor->_decomp_asbd.mBytesPerFrame;
  debug_assert(pic->linesize[0] <= (int)decompressor->_decompression_buffer_length);
  debug_assert(pic->nb_samples == MPEG_AUDIO_LAYER_2_FRAMES_PER_PACKET);
  return 0;
}

static void MHKMP2Decompressor_release_buffer(struct AVCodecContext* c, AVFrame* pic)
{
  pic->data[0] = NULL;
  pic->extended_data[0] = NULL;
  pic->linesize[0] = 0;
}

+ (void)loadLibav
{
#if defined(DEBUG) && DEBUG > 1
  NSLog(@"initializing libav...");
#endif

  // load the function pointers we need

  _libav_state.avcodec_register_all = dlsym(_libav_state.avcodec_handle, "avcodec_register_all");
  if (!_libav_state.avcodec_register_all) {
    NSLog(@"unable to bind symbol \"avcodec_register_all\": %s", dlerror());
    abort();
  }

  _libav_state.av_freep = dlsym(_libav_state.avcodec_handle, "av_freep");
  if (!_libav_state.av_freep) {
    NSLog(@"unable to bind symbol \"av_freep\": %s", dlerror());
    abort();
  }

  _libav_state.avcodec_find_decoder = dlsym(_libav_state.avcodec_handle, "avcodec_find_decoder");
  if (!_libav_state.avcodec_find_decoder) {
    NSLog(@"unable to bind symbol \"avcodec_find_decoder\": %s", dlerror());
    abort();
  }

  _libav_state.avcodec_alloc_context3 = dlsym(_libav_state.avcodec_handle, "avcodec_alloc_context3");
  if (!_libav_state.avcodec_alloc_context3) {
    NSLog(@"unable to bind symbol \"avcodec_alloc_context3\": %s", dlerror());
    abort();
  }

  _libav_state.avcodec_open2 = dlsym(_libav_state.avcodec_handle, "avcodec_open2");
  if (!_libav_state.avcodec_open2) {
    NSLog(@"unable to bind symbol \"avcodec_open2\": %s", dlerror());
    abort();
  }

  _libav_state.avcodec_close = dlsym(_libav_state.avcodec_handle, "avcodec_close");
  if (!_libav_state.avcodec_close) {
    NSLog(@"unable to bind symbol \"avcodec_close\": %s", dlerror());
    abort();
  }

  _libav_state.avcodec_alloc_frame = dlsym(_libav_state.avcodec_handle, "avcodec_alloc_frame");
  if (!_libav_state.avcodec_alloc_frame) {
    NSLog(@"unable to bind symbol \"avcodec_alloc_frame\": %s", dlerror());
    abort();
  }

  _libav_state.avcodec_free_frame = dlsym(_libav_state.avcodec_handle, "avcodec_free_frame");
  if (!_libav_state.avcodec_free_frame) {
    NSLog(@"unable to bind symbol \"avcodec_free_frame\": %s", dlerror());
    abort();
  }

  _libav_state.avcodec_decode_audio4 = dlsym(_libav_state.avcodec_handle, "avcodec_decode_audio4");
  if (!_libav_state.avcodec_decode_audio4) {
    NSLog(@"unable to bind symbol \"avcodec_decode_audio4\": %s", dlerror());
    abort();
  }

  // initialize libavcodec and the MPEG 1/2 audio layer decoder
  _libav_state.avcodec_register_all();
  _libav_state.mp2_codec = _libav_state.avcodec_find_decoder(AV_CODEC_ID_MP2);

  // libav mutex
  pthread_mutex_init(&s_libav_mutex, NULL);
}

+ (void)initialize
{
  static BOOL MHKMP2Decompressor_has_initialized = NO;
  if (!MHKMP2Decompressor_has_initialized) {
    MHKMP2Decompressor_has_initialized = YES;

    // get a bundle to MHKKit and the path to the Resources directory
    NSBundle* mhk_bundle = [NSBundle bundleForClass:[self class]];
    NSString* resource_path = [mhk_bundle resourcePath];
    char* error_string = NULL;

    // load libavcodec
    _libav_state.avcodec_handle =
        dlopen([[resource_path stringByAppendingPathComponent:@"libavcodec.dylib"] fileSystemRepresentation], RTLD_LAZY | RTLD_GLOBAL);
    error_string = dlerror();
    if (error_string)
      fprintf(stderr, "%s\n", error_string);
    if (!_libav_state.avcodec_handle)
      return;

    // load libav if we were able to link libavcodec
    if (_libav_state.avcodec_handle) {
      MHKMP2Decompressor_libav_available = YES;
      [self loadLibav];
    }
  }
}

- (BOOL)_build_packet_description_table_and_count_frames:(NSError**)error
{
  NSError* local_error = nil;

  uint8_t* read_buffer = malloc(READ_BUFFER_SIZE);
  ssize_t size_left_in_buffer = 0;
  uint32_t buffer_position = 0;

  const off_t source_length = [_data_source length];
  off_t source_position = [_data_source offsetInFile];

  // initialize the packet count
  _packet_count = 0;

  // start with say 1000 packets
  ssize_t packet_table_length = 1000;
  _packet_table = calloc(packet_table_length, sizeof(AudioStreamPacketDescription));
  if (!_packet_table) {
    free(read_buffer);
    ReturnValueWithPOSIXError(NO, nil, error);
  }

  // loop while we still have data left to process
  while (source_position < source_length) {
    // is the read buffer empty?
    if (size_left_in_buffer == 0) {
      size_left_in_buffer = [_data_source readDataOfLength:READ_BUFFER_SIZE inBuffer:read_buffer error:&local_error];
      if (size_left_in_buffer == -1) {
        free(read_buffer);
        ReturnValueWithError(NO, [local_error domain], [local_error code], [local_error userInfo], error);
      }

      if (size_left_in_buffer == 0 && [local_error code] == eofErr)
        break;

      source_position = [_data_source offsetInFile];
      buffer_position = 0;
    }

    // find the next frame sync
    while (size_left_in_buffer >= 4) {
      uint32_t mpeg_header;
      memcpy(&mpeg_header, read_buffer, sizeof(uint32_t));
      mpeg_header = CFSwapInt32BigToHost(mpeg_header);
      if (!_valid_mpeg_audio_frame_header_predicate(mpeg_header)) {
        buffer_position++;
        size_left_in_buffer--;
        continue;
      }

      // compute the frame length to seek to the next frame
      size_t frame_length = _compute_mpeg_audio_frame_length(mpeg_header);

      // load up the packet description entry
      _packet_table[_packet_count].mStartOffset = source_position - size_left_in_buffer;
      _packet_table[_packet_count].mDataByteSize = frame_length;
      _packet_table[_packet_count].mVariableFramesInPacket = 0;

      // one packet for the team
      _packet_count++;

      // update the maximum packet size
      if (frame_length > _max_packet_size)
        _max_packet_size = frame_length;

      // do we need a bigger packet table?
      if (packet_table_length == _packet_count) {
        packet_table_length *= 2;
        _packet_table = realloc(_packet_table, packet_table_length * sizeof(AudioStreamPacketDescription));
        if (!_packet_table) {
          free(read_buffer);
          ReturnValueWithPOSIXError(NO, nil, error);
        }
      }

      // if the whole frame isn't in the buffer, fill it up
      if ((size_t)size_left_in_buffer < frame_length) {
        memmove(read_buffer, read_buffer + buffer_position, size_left_in_buffer);

        size_left_in_buffer +=
            [_data_source readDataOfLength:(READ_BUFFER_SIZE - size_left_in_buffer)inBuffer:(read_buffer + size_left_in_buffer)error:&local_error];
        if (size_left_in_buffer == -1) {
          free(read_buffer);
          ReturnValueWithError(NO, [local_error domain], [local_error code], [local_error userInfo], error);
        }

        if (size_left_in_buffer == 0 && [local_error code] == eofErr)
          break;

        source_position = [_data_source offsetInFile];
        buffer_position = 0;
      }

      // move past the frame in the read buffer
      buffer_position += frame_length;
      size_left_in_buffer -= frame_length;
    }

    // if we have 3 or less but not 0 bytes left in the buffer, move them up front and read some more bytes
    if (size_left_in_buffer < 4 && size_left_in_buffer > 0) {
      memmove(read_buffer, read_buffer + buffer_position, size_left_in_buffer);

      size_left_in_buffer +=
          [_data_source readDataOfLength:(READ_BUFFER_SIZE - size_left_in_buffer)inBuffer:(read_buffer + size_left_in_buffer)error:&local_error];
      if (size_left_in_buffer == -1) {
        free(read_buffer);
        ReturnValueWithError(NO, [local_error domain], [local_error code], [local_error userInfo], error);
      }

      if (size_left_in_buffer == 0 && [local_error code] == eofErr)
        break;

      source_position = [_data_source offsetInFile];
      buffer_position = 0;
    }
  }

  free(read_buffer);
  return YES;
}

- (id)init
{
  [self doesNotRecognizeSelector:_cmd];
  [self release];
  return nil;
}

- (id)initWithChannelCount:(UInt32)channels frameCount:(SInt64)frames samplingRate:(double)sps fileHandle:(MHKFileHandle*)fh error:(NSError**)errorPtr
{
  self = [super init];
  if (!self)
    return nil;

  // we can't do anything without libav
  if (!MHKMP2Decompressor_libav_available) {
    [self release];
    ReturnValueWithError(nil, MHKErrorDomain, errLibavNotAvailable, nil, errorPtr);
  }

  // layer II audio can only store 1 or 2 channels
  if (channels != 1 && channels != 2) {
    [self release];
    ReturnValueWithError(nil, MHKErrorDomain, errInvalidChannelCount, nil, errorPtr);
  }

  _channel_count = channels;
  _frame_count = frames;
  _data_source = [fh retain];

  // setup the decompression ABSD
  _decomp_asbd.mFormatID = kAudioFormatLinearPCM;
  _decomp_asbd.mFormatFlags = kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
  _decomp_asbd.mSampleRate = sps;
  _decomp_asbd.mChannelsPerFrame = _channel_count;
  _decomp_asbd.mBitsPerChannel = 16;
  _decomp_asbd.mFramesPerPacket = 1;
  _decomp_asbd.mBytesPerFrame = _decomp_asbd.mChannelsPerFrame * _decomp_asbd.mBitsPerChannel / 8;
  _decomp_asbd.mBytesPerPacket = _decomp_asbd.mFramesPerPacket * _decomp_asbd.mBytesPerFrame;

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
  } else
    _audio_packets_start_offset = 0;

  // seek to the first audio data packet
  [_data_source seekToFileOffset:_audio_packets_start_offset];

  // build the packet description table
  _max_packet_size = 0;
  if (![self _build_packet_description_table_and_count_frames:&local_error]) {
    if (errorPtr)
      *errorPtr = local_error;
    [self release];
    return nil;
  }

  // compute the integer (audio) frame count (layer II always uses 1152 audio frames per MPEG frames)
  SInt64 integer_frame_count = _packet_count * MPEG_AUDIO_LAYER_2_FRAMES_PER_PACKET;

  // if we're told we have more frames than we can have, bail
  if (_frame_count > integer_frame_count) {
    [self release];
    ReturnValueWithError(nil, MHKErrorDomain, errInvalidFrameCount, nil, errorPtr);
  }

  // compute how many bytes we should drop from the first packet (where extra silence will be)
  _bytes_to_drop = FRAME_SKIP_FUDGE * _decomp_asbd.mBytesPerFrame;

  // allocate the decompression buffer
  _decompression_buffer_length = MAX(MPEG_AUDIO_LAYER_2_FRAMES_PER_PACKET * sizeof(SInt16) * _channel_count, AVCODEC_MAX_AUDIO_FRAME_SIZE);
  _decompression_buffer = malloc(_decompression_buffer_length + FF_INPUT_BUFFER_PADDING_SIZE);
  if (!_decompression_buffer) {
    [self release];
    ReturnValueWithError(nil, NSPOSIXErrorDomain, errno, nil, errorPtr);
  }
  memset(BUFFER_OFFSET(_decompression_buffer, _decompression_buffer_length), 0, FF_INPUT_BUFFER_PADDING_SIZE);

  // allocate the packet buffer
  _packet_buffer = malloc(_max_packet_size * 50);
  if (!_packet_buffer) {
    [self release];
    ReturnValueWithError(nil, NSPOSIXErrorDomain, errno, nil, errorPtr);
  }

  // create the decompressor lock
  pthread_mutex_init(&_decompressor_lock, NULL);

  // finish initialization by resetting the decompressor (which will create the libav context and open the libav codec)
  [self reset];

  return self;
}

- (void)dealloc
{
  // close the decoder
  pthread_mutex_lock(&s_libav_mutex);
  if (_mp2_codec_context) {
    _libav_state.avcodec_close(_mp2_codec_context);
    _libav_state.av_freep(&_mp2_codec_context);
    _libav_state.avcodec_free_frame(&_mp2_frame);
  }
  pthread_mutex_unlock(&s_libav_mutex);

  // free memory resources
  if (_packet_buffer)
    free(_packet_buffer);
  if (_decompression_buffer)
    free(_decompression_buffer);
  if (_packet_table)
    free(_packet_table);

  [_data_source release];

  pthread_mutex_destroy(&_decompressor_lock);

  [super dealloc];
}

- (AudioStreamBasicDescription)outputFormat { return _decomp_asbd; }

- (SInt64)frameCount { return _frame_count; }

- (void)reset
{
  pthread_mutex_lock(&_decompressor_lock);

#if defined(DEBUG) && DEBUG > 1
  NSLog(@"%@: resetting", self);
#endif

  // seek to the first audio data packet
  [_data_source seekToFileOffset:_audio_packets_start_offset];

  // reset the decompression buffer
  _decompression_buffer_position = 0;
  _decompression_buffer_available = 0;

  // start at the first packet, no packets available initially, current packet set to the read buffer's head
  _packet_index = 0;
  _available_packets = 0;
  _current_packet = _packet_buffer;

  // close and re-open the codec context
  pthread_mutex_lock(&s_libav_mutex);

  if (_mp2_codec_context) {
    _libav_state.avcodec_close(_mp2_codec_context);
    _libav_state.av_freep(&_mp2_codec_context);
    _libav_state.avcodec_free_frame(&_mp2_frame);
  }

  // allocate the codec context
  _mp2_codec_context = _libav_state.avcodec_alloc_context3(_libav_state.mp2_codec);
  if (!_mp2_codec_context) {
    fprintf(stderr, "<MHKMP2Decompressor %p>: avcodec_alloc_context3 failed\n", self);
  } else {
    // configure the context
    _mp2_codec_context->opaque = self;
    _mp2_codec_context->get_buffer = MHKMP2Decompressor_get_buffer;
    _mp2_codec_context->release_buffer = MHKMP2Decompressor_release_buffer;
    _mp2_codec_context->request_sample_fmt = AV_SAMPLE_FMT_S16;

    // open the codec
    int result = _libav_state.avcodec_open2(_mp2_codec_context, _libav_state.mp2_codec, NULL);
    if (result < 0)
      fprintf(stderr, "<MHKMP2Decompressor %p>: avcodec_open2 failed: %d\n", self, result);

    // allocate decompression frame
    _mp2_frame = _libav_state.avcodec_alloc_frame();
  }

  pthread_mutex_unlock(&s_libav_mutex);
  pthread_mutex_unlock(&_decompressor_lock);
}

- (void)fillAudioBufferList:(AudioBufferList*)abl
{
  // we can't handle de-interleaved ABLs
  debug_assert(abl->mNumberBuffers == 1);

  // take the decompressor lock
  pthread_mutex_lock(&_decompressor_lock);

  // bytes_to_decompress is a fixed quantity which is set to the total number
  // of bytes to copy into the ABL
  size_t const bytes_to_decompress = abl->mBuffers[0].mDataByteSize;
  debug_assert(bytes_to_decompress % _decomp_asbd.mBytesPerFrame == 0);

  // decompressed_bytes tracks the number of bytes that have been copied into
  // the ABL, and is essentially the ABL buffer offset
  size_t decompressed_bytes = 0;

  // available_bytes is a volatile quantity used to track available bytes to
  // copy into the ABL buffer
  size_t bytes_to_copy = 0;

  // if we have frames left from the last fill, copy them in
  if (_decompression_buffer_available > 0) {
    // compute how many bytes we can copy
    bytes_to_copy = _decompression_buffer_available;
    if (bytes_to_copy > bytes_to_decompress - decompressed_bytes)
      bytes_to_copy = bytes_to_decompress - decompressed_bytes;

    // copy the bytes
    memcpy(BUFFER_OFFSET(abl->mBuffers[0].mData, decompressed_bytes), BUFFER_OFFSET(_decompression_buffer, _decompression_buffer_position), bytes_to_copy);
    decompressed_bytes += bytes_to_copy;
    _decompression_buffer_position += bytes_to_copy;
    _decompression_buffer_available -= bytes_to_copy;

    // fast return if we're all done
    if (bytes_to_decompress == decompressed_bytes)
      goto AbortFill;
  }

  // at this point the decompression buffer must be empty
  debug_assert(_decompression_buffer_available == 0);

  // if we don't have a valid libav context, abort out
  if (!_mp2_codec_context)
    goto AbortFill;

  // decompress until we have filled the ABL or ran out of packets
  while (bytes_to_decompress > decompressed_bytes && _packet_index < _packet_count) {
    // at this point, we've exhausted the decompression buffer and we have
    // to decompress a new packet; hence, this loop body never offsets the
    // decompression buffer by its position

    // as a corrolary to the above, we reset the decompression buffer
    // position to 0 so that if this is the last iteration of the packet
    // decompression loop, the position will be ready for the spill-over
    // copy loop above
    _decompression_buffer_position = 0;

    // if we ran out of packets in memory, read some more
    if (_available_packets == 0) {
      // compute the length of an integral number of packets that we can read, up to 50 packets
      uint32_t bytes_to_read = _max_packet_size * 50;
      if (bytes_to_read > [_data_source length] - [_data_source offsetInFile]) {
        // explicit cast OK here, API limited to 32-bit read sizes
        bytes_to_read = (UInt32)((([_data_source length] - [_data_source offsetInFile]) / _max_packet_size) * _max_packet_size);
      }

      // read the packets
      ssize_t bytes_read = [_data_source readDataOfLength:bytes_to_read inBuffer:_packet_buffer error:nil];
      if ((size_t)bytes_read != bytes_to_read)
        goto AbortFill;

      // reset the packet buffer state
      _available_packets = bytes_read / _max_packet_size;
      _current_packet = _packet_buffer;
    }

    // decompress a packet

    struct AVPacket packet;
    packet.pts = AV_NOPTS_VALUE;
    packet.dts = AV_NOPTS_VALUE;
    packet.data = _current_packet;
    packet.size = _packet_table[_packet_index].mDataByteSize;
    packet.stream_index = 0;
    packet.flags = 0;
    packet.side_data = NULL;
    packet.side_data_elems = 0;
    packet.duration = 0;
    packet.destruct = NULL;
    packet.priv = NULL;
    packet.pos = -1;
    packet.convergence_duration = AV_NOPTS_VALUE;

    int got_frame_ptr;
    int used_bytes = _libav_state.avcodec_decode_audio4(_mp2_codec_context, _mp2_frame, &got_frame_ptr, &packet);
    if (used_bytes <= 0)
      goto AbortFill;

    _decompression_buffer_available = _mp2_frame->linesize[0];

    // the output buffer size is the initial number of bytes to copy
    bytes_to_copy = _decompression_buffer_available;

    // apply the frame skip hack on the first packet
    if (_packet_index == 0) {
      // temporarily advance the decompression buffer and reduce the number of bytes to copy
      _decompression_buffer = BUFFER_OFFSET(_decompression_buffer, _bytes_to_drop);
      bytes_to_copy -= _bytes_to_drop;
    }

    // adjust the number of bytes to copy to the ABL buffer size
    if (bytes_to_copy > bytes_to_decompress - decompressed_bytes)
      bytes_to_copy = bytes_to_decompress - decompressed_bytes;

    // copy the bytes
    memcpy(BUFFER_OFFSET(abl->mBuffers[0].mData, decompressed_bytes), _decompression_buffer, bytes_to_copy);
    decompressed_bytes += bytes_to_copy;
    _decompression_buffer_position += bytes_to_copy;
    _decompression_buffer_available -= bytes_to_copy;

    // compensate and undo for the first packet frame skip hack
    if (_packet_index == 0) {
      _decompression_buffer = BUFFER_NOFFSET(_decompression_buffer, _bytes_to_drop);
      _decompression_buffer_position += _bytes_to_drop;
      _decompression_buffer_available -= _bytes_to_drop;
    }

    // move on to the next packet
    _current_packet = BUFFER_OFFSET(_current_packet, _packet_table[_packet_index].mDataByteSize);
    --_available_packets;
    ++_packet_index;
  }

AbortFill:
  // zero left-over frames
  if (bytes_to_decompress > decompressed_bytes) {
#if defined(DEBUG) && DEBUG > 1
    NSLog(@"%@: zero filling tail of ABL buffer on packet %lld/%lld", self, _packet_index, _packet_count);
#endif
    bzero(BUFFER_OFFSET(abl->mBuffers[0].mData, decompressed_bytes), bytes_to_decompress - decompressed_bytes);
  }

  pthread_mutex_unlock(&_decompressor_lock);
}

@end
