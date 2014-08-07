// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include <MHKKit/mohawk_core.h>

// Normal signatures
extern const char MHK_WAVE_signature[4];
extern const char MHK_Cue_signature[4];
extern const char MHK_ADPC_signature[4];
extern const char MHK_Data_signature[4];

// Integer signatures
extern const uint32_t MHK_WAVE_signature_integer;
extern const uint32_t MHK_Cue_signature_integer;
extern const uint32_t MHK_ADPC_signature_integer;
extern const uint32_t MHK_Data_signature_integer;

// Compression constants
extern const int MHK_WAVE_ADPCM;
extern const int MHK_WAVE_MP2;

// File structures, turn on packing

#pragma pack(push, 1)
typedef struct {
  uint16_t sampling_rate;
  uint32_t frame_count;
  uint8_t bit_depth;
  uint8_t channel_count;
  uint16_t compression_type;
  uint16_t loop_count;
  uint32_t loop_start;
  uint32_t loop_end;
} MHK_WAVE_Data_header;
#pragma pack(pop)

// Byte order utilities
// f == file, n == native

static inline void MHK_WAVE_Data_header_fton(MHK_WAVE_Data_header* s) {
  s->sampling_rate = OSSwapBigToHostInt16(s->sampling_rate);
  s->frame_count = OSSwapBigToHostInt32(s->frame_count);
  s->compression_type = OSSwapBigToHostInt16(s->compression_type);
  s->loop_count = OSSwapBigToHostInt16(s->loop_count);
  s->loop_start = OSSwapBigToHostInt32(s->loop_start);
  s->loop_end = OSSwapBigToHostInt32(s->loop_end);
}
