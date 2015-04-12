// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "mhk/MHKLibAVAudioDecompressor.h"

#import <vector>

#import "Base/RXBufferMacros.h"
#import "Base/RXErrorMacros.h"

#import "mhk/mohawk_libav.h"
#import "mhk/mohawk_sound.h"

#import "mhk/MHKArchiveMediaInterface.h"
#import "mhk/MHKErrors.h"
#import "mhk/MHKFileHandle.h"
#import "mhk/MHKLibAVIOContext.h"

static const size_t IO_BUFFER_SIZE = 0x1000;

static void FillAsbdFromLibAvFormat(AudioStreamBasicDescription& asbd,
                                    const AVSampleFormat format) {
  size_t sample_size = 0;
  if (format == AV_SAMPLE_FMT_FLT || format == AV_SAMPLE_FMT_FLTP) {
    asbd.mFormatFlags |= kAudioFormatFlagIsFloat;
    sample_size = sizeof(float);
  } else if (format == AV_SAMPLE_FMT_DBL || format == AV_SAMPLE_FMT_DBLP) {
    asbd.mFormatFlags |= kAudioFormatFlagIsFloat;
    sample_size = sizeof(double);
  } else if (format == AV_SAMPLE_FMT_U8 || format == AV_SAMPLE_FMT_U8P) {
    sample_size = sizeof(int8_t);
  } else if (format == AV_SAMPLE_FMT_S16 || format == AV_SAMPLE_FMT_S16P) {
    asbd.mFormatFlags |= kAudioFormatFlagIsSignedInteger;
    sample_size = sizeof(int16_t);
  } else if (format == AV_SAMPLE_FMT_S32 || format == AV_SAMPLE_FMT_S32P) {
    asbd.mFormatFlags |= kAudioFormatFlagIsSignedInteger;
    sample_size = sizeof(int32_t);
  }
  if (sample_size == 0) {
    return;
  }

  switch (format) {
    case AV_SAMPLE_FMT_U8P:
    case AV_SAMPLE_FMT_S16P:
    case AV_SAMPLE_FMT_S32P:
    case AV_SAMPLE_FMT_FLTP:
    case AV_SAMPLE_FMT_DBLP:
      asbd.mFormatFlags |= kAudioFormatFlagIsNonInterleaved;
      break;
    default:
      break;
  }

  asbd.mFormatFlags |= kAudioFormatFlagIsPacked;

  asbd.mFramesPerPacket = 1;
  asbd.mBitsPerChannel = (uint32_t)sample_size * 8;
  if ((asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved)) {
    asbd.mBytesPerFrame = asbd.mBytesPerPacket = (uint32_t)sample_size;
  } else {
    asbd.mBytesPerFrame = asbd.mBytesPerPacket = (uint32_t)sample_size * asbd.mChannelsPerFrame;
  }
}

@implementation MHKLibAVAudioDecompressor {
  // mp2
  MHKLibAVIOContext* _ioContext;
  AVFormatContext* _formatContext;

  // adpcm
  AVCodecContext* _adpcmCodecContext;

  // common
  MHKFileHandle* _fileHandle;
  AudioStreamBasicDescription _outputFormat;

  AVPacket _packet;
  AVFrame* _frame;
  uint32_t _frameCursor;
  uint32_t _firstPacketFrameDelay;
}

@dynamic outputFormat;

+ (void)initialize {
  if (self == [MHKLibAVAudioDecompressor class]) {
    mhk_load_libav();
  }
}

- (instancetype)init {
  [self doesNotRecognizeSelector:_cmd];
  return [self initWithSoundDescriptor:nil fileHandle:nil error:NULL];
}

- (instancetype)initWithSoundDescriptor:(MHKSoundDescriptor*)sdesc
                             fileHandle:(MHKFileHandle*)fileHandle
                                  error:(NSError**)outError {
  self = [super init];
  if (!self) {
    return nil;
  }

  if (!sdesc || !fileHandle) {
    [self release];
    return nil;
  }

  if (!g_libav.avu_handle) {
    [self release];
    ReturnValueWithError(nil, MHKErrorDomain, errLibavNotAvailable, nil, outError);
  }

  _fileHandle = [fileHandle retain];
  _frameCount = sdesc.frameCount;

  _outputFormat.mSampleRate = sdesc.sampleRate;
  _outputFormat.mFormatID = kAudioFormatLinearPCM;
  _outputFormat.mFormatFlags = 0;
  _outputFormat.mChannelsPerFrame = sdesc.channelCount;

  const uint16_t compression = sdesc.compressionType;
  BOOL initialized = NO;
  if (compression == MHK_WAVE_ADPCM) {
    initialized = [self _initAdpcm:sdesc];
  } else if (compression == MHK_WAVE_MP2) {
    initialized = [self _initMp2:sdesc];
  } else {
    ReturnValueWithError(nil, MHKErrorDomain, errInvalidSoundDescriptor, nil, outError);
  }

  if (!initialized) {
    [self release];
    ReturnValueWithError(nil, MHKErrorDomain, errLibavError, nil, outError);
  }
  debug_assert(_framesPerPacket > 0);

  _frame = g_libav.av_frame_alloc();

  return self;
}

- (void)dealloc {
  if (_formatContext) {
    g_libav.avcodec_close(_formatContext->streams[0]->codec);
    g_libav.avformat_close_input(&_formatContext);
    [_ioContext release];
  }
  if (_adpcmCodecContext) {
    g_libav.avcodec_close(_adpcmCodecContext);
    g_libav.av_freep(&_adpcmCodecContext);
  }
  g_libav.av_frame_free(&_frame);
  g_libav.av_free_packet(&_packet);
  [_fileHandle release];

  [super dealloc];
}

- (const AudioStreamBasicDescription*)outputFormat {
  return &_outputFormat;
}

- (BOOL)_initAdpcm:(MHKSoundDescriptor*)sdesc {
  AVCodec* codec = g_libav.avcodec_find_decoder(AV_CODEC_ID_ADPCM_IMA_APC);
  if (!codec) {
    return NO;
  }
  debug_assert((codec->capabilities & CODEC_CAP_DELAY) == 0);

  if (![self _resetAdpcmCodecContext:codec
                          sampleRate:sdesc.sampleRate
                        channelCount:sdesc.channelCount]) {
    return NO;
  }

  FillAsbdFromLibAvFormat(_outputFormat, _adpcmCodecContext->sample_fmt);
  if (_outputFormat.mFormatFlags == 0) {
    return NO;
  }

  g_libav.av_new_packet(&_packet, IO_BUFFER_SIZE);
  _packet.size = 0;

  _framesPerPacket = IO_BUFFER_SIZE * 2 / sdesc.channelCount;

  return YES;
}

- (BOOL)_resetAdpcmCodecContext:(const AVCodec*)codec
                     sampleRate:(uint16_t)sampleRate
                   channelCount:(uint8_t)channelCount {
  if (_adpcmCodecContext) {
    g_libav.avcodec_close(_adpcmCodecContext);
    g_libav.av_freep(&_adpcmCodecContext);
  }

  _adpcmCodecContext = g_libav.avcodec_alloc_context3(codec);
  _adpcmCodecContext->sample_rate = sampleRate;
  _adpcmCodecContext->channels = channelCount;
  _adpcmCodecContext->request_sample_fmt = AV_SAMPLE_FMT_S16;
  _adpcmCodecContext->refcounted_frames = 1;

  return g_libav.avcodec_open2(_adpcmCodecContext, codec, nullptr) >= 0;
}

- (BOOL)_initMp2:(MHKSoundDescriptor*)sdesc {
  AVInputFormat* input_format = g_libav.av_iformat_next(nullptr);
  while (input_format) {
    if (strstr(input_format->name, "mp3") != nullptr) {
      break;
    }
    input_format = g_libav.av_iformat_next(input_format);
  }
  if (!input_format) {
    return NO;
  }

  _ioContext = [[MHKLibAVIOContext alloc] initWithFileHandle:_fileHandle error:nullptr];

  _formatContext = g_libav.avformat_alloc_context();
  _formatContext->pb = _ioContext.avioc;

  if (g_libav.avformat_open_input(&_formatContext, "", input_format, nullptr) < 0) {
    return NO;
  }
  if (_formatContext->nb_streams != 1) {
    return NO;
  }

  _formatContext->streams[0]->nb_frames = sdesc.frameCount;
  _formatContext->streams[0]->duration = sdesc.frameCount * sdesc.sampleRate *
                                         _formatContext->streams[0]->time_base.num /
                                         _formatContext->streams[0]->time_base.den;

  std::vector<AVDictionary*> stream_options(_formatContext->nb_streams);
  if (g_libav.avformat_find_stream_info(_formatContext, &stream_options.front()) < 0) {
    return NO;
  }

  AVCodec* codec = g_libav.avcodec_find_decoder(_formatContext->streams[0]->codec->codec_id);
  if (!codec) {
    return NO;
  }
  debug_assert((codec->capabilities & CODEC_CAP_DELAY) == 0);

  debug_assert(_formatContext->streams[0]->codec->codec_type == AVMEDIA_TYPE_AUDIO);
  debug_assert(_formatContext->streams[0]->codec->sample_rate == sdesc.sampleRate);
  debug_assert(_formatContext->streams[0]->codec->channels == sdesc.channelCount);
  _formatContext->streams[0]->codec->refcounted_frames = 1;
  _formatContext->streams[0]->codec->request_sample_fmt = AV_SAMPLE_FMT_S16;
  if (g_libav.avcodec_open2(_formatContext->streams[0]->codec, codec, nullptr) < 0) {
    return NO;
  }

  FillAsbdFromLibAvFormat(_outputFormat, _formatContext->streams[0]->codec->sample_fmt);
  if (_outputFormat.mFormatFlags == 0) {
    return NO;
  }

  // these values are intrinsic to the mp2 codec, but libav doesn't provide a nice way to query them
  _firstPacketFrameDelay = 481;
  _framesPerPacket = 1152;

  return YES;
}

- (void)reset {
  if (_formatContext) {
    g_libav.avio_seek(_formatContext->pb, 0, SEEK_SET);
    g_libav.av_free_packet(&_packet);
    g_libav.avcodec_flush_buffers(_formatContext->streams[0]->codec);
  } else {
    // the adpcm codec can't seek, we need to tear it down
    [_fileHandle seekToFileOffset:0];
    _packet.size = 0;
    [self _resetAdpcmCodecContext:_adpcmCodecContext->codec
                       sampleRate:(uint16_t)_outputFormat.mSampleRate
                     channelCount:(uint8_t)_outputFormat.mChannelsPerFrame];
  }

  g_libav.av_frame_unref(_frame);
  _frameCursor = 0;
  _framePosition = 0;
}

- (uint32_t)fillAudioBufferList:(AudioBufferList*)abl {
  debug_assert(abl);
  debug_assert(abl->mNumberBuffers ==
                       (_outputFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved)
                   ? _outputFormat.mChannelsPerFrame
                   : 1);
#if DEBUG
  for (uint32_t i = 1; i < abl->mNumberBuffers; ++i) {
    debug_assert(abl->mBuffers[0].mDataByteSize == abl->mBuffers[i].mDataByteSize);
  }
#endif

  uint32_t frames_left = abl->mBuffers[0].mDataByteSize / _outputFormat.mBytesPerFrame;
  uint32_t frame_cursor = 0;
  uint32_t frames_copied = 1;
  while (frames_left > 0 && frames_copied > 0) {
    frames_copied = [self _outputFrames:abl cursor:frame_cursor left:frames_left];
    frames_left -= frames_copied;
    frame_cursor += frames_copied;
  }
  return frame_cursor;
}

- (uint32_t)_outputFrames:(AudioBufferList*)abl cursor:(uint32_t)cursor left:(uint32_t)left {
  // if there are no frames available, decode the next packet
  debug_assert((uint32_t)_frame->nb_samples >= _frameCursor);
  auto decoded_frame_count =
      std::min(_frame->nb_samples - _frameCursor, uint32_t(_frameCount - _framePosition));
  if (decoded_frame_count == 0) {
    [self _decodePacket];
    _frameCursor = (_framePosition == 0) ? _firstPacketFrameDelay : 0;
    decoded_frame_count =
        std::min(_frame->nb_samples - _frameCursor, uint32_t(_frameCount - _framePosition));
  }

  // copy min(frames we can store, frames we have)
  uint32_t frame_count = std::min<uint32_t>(left, decoded_frame_count);
  if (frame_count == 0) {
    return 0;
  }

  // copy each buffer of samples (there will be one for interleaved formats)
  auto frame_bytes = frame_count * _outputFormat.mBytesPerFrame;
  for (uint32_t i = 0; i < abl->mNumberBuffers; ++i) {
    auto out_ptr = rx::BUFFER_OFFSET(abl->mBuffers[i].mData, cursor * _outputFormat.mBytesPerFrame);
    auto in_ptr = rx::BUFFER_OFFSET(_frame->data[i], _frameCursor * _outputFormat.mBytesPerFrame);

    debug_assert(rx::BUFFER_OFFSET(out_ptr, frame_bytes) <=
                 rx::BUFFER_OFFSET(abl->mBuffers[i].mData, abl->mBuffers[i].mDataByteSize));
    debug_assert(rx::BUFFER_OFFSET(in_ptr, frame_bytes) <=
                 rx::BUFFER_OFFSET(_frame->data[i], _frame->linesize[0]));

    memcpy(out_ptr, in_ptr, frame_bytes);
  }

  _frameCursor += frame_count;
  _framePosition += frame_count;

  return frame_count;
}

- (void)_decodePacket {
  // we've completely consumed the previous decoded frame
  g_libav.av_frame_unref(_frame);

  // if the packet is empty, read the next packet
  if (_packet.size == 0) {
    if (_formatContext) {
      g_libav.av_free_packet(&_packet);
      if (g_libav.av_read_frame(_formatContext, &_packet) < 0) {
        return;
      }
      debug_assert(_packet.stream_index == 0);
    } else {
      _packet.data = _packet.buf->data;
      _packet.size =
          (int)[_fileHandle readDataOfLength:IO_BUFFER_SIZE inBuffer:_packet.data error:nullptr];
      if (_packet.size <= 0) {
        return;
      }
    }
  }

  // the codec context we'll use for decoding
  AVCodecContext* codec_context;
  if (_formatContext) {
    codec_context = _formatContext->streams[0]->codec;
  } else {
    codec_context = _adpcmCodecContext;
  }

  // decode the packet
  int got_output;
  int bytes_consumed = g_libav.avcodec_decode_audio4(codec_context, _frame, &got_output, &_packet);
  if (bytes_consumed < 0) {
    return;
  }
  debug_assert(got_output);

  // advance the packet data (decoding may not consume the entire packet)
  _packet.data += bytes_consumed;
  _packet.size -= bytes_consumed;
}

@end
