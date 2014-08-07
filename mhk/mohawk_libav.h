// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include <sys/cdefs.h>

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>

__BEGIN_DECLS

struct mhk_libav {
  void* avu_handle;
  void* avc_handle;
  void* avf_handle;

  void* (*av_malloc)(size_t);
  void (*av_freep)(void*);
  void (*av_log_set_level)(int);
  int (*av_dict_set)(AVDictionary**, const char*, const char*, int);
  AVFrame* (*av_frame_alloc)(void);
  void (*av_frame_unref)(AVFrame*);
  void (*av_frame_free)(AVFrame**);

  void (*avcodec_register_all)(void);
  AVCodec* (*avcodec_find_decoder)(enum AVCodecID);
  AVCodecContext* (*avcodec_alloc_context3)(const AVCodec*);
  int (*avcodec_open2)(AVCodecContext*, const AVCodec*, AVDictionary**);
  int (*avcodec_close)(AVCodecContext*);
  void (*av_init_packet)(AVPacket*);
  int (*av_new_packet)(AVPacket*, int);
  void (*av_free_packet)(AVPacket*);
  void (*avcodec_flush_buffers)(AVCodecContext*);
  int (*avcodec_decode_audio4)(AVCodecContext*, AVFrame*, int*, AVPacket*);

  void (*av_register_all)(void);
  AVInputFormat* (*av_iformat_next)(AVInputFormat*);
  AVFormatContext* (*avformat_alloc_context)(void);
  void (*avformat_free_context)(AVFormatContext*);
  int (*avformat_open_input)(AVFormatContext**, const char*, AVInputFormat*, AVDictionary**);
  int (*avformat_find_stream_info)(AVFormatContext*, AVDictionary**);
  int (*av_read_frame)(AVFormatContext*, AVPacket*);
  void (*avformat_close_input)(AVFormatContext**);

  AVIOContext* (*avio_alloc_context)(unsigned char*,
                                     int,
                                     int,
                                     void*,
                                     int (*)(void*, uint8_t*, int),
                                     int (*)(void*, uint8_t*, int),
                                     int64_t (*)(void*, int64_t, int));
  int64_t (*avio_seek)(AVIOContext*, int64_t, int);
};

extern struct mhk_libav g_libav;
extern void mhk_load_libav(void);

__END_DECLS
