// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include <MHKKit/mohawk_core.h>

// Compression constants
extern const int MHK_BITMAP_RAW;
extern const int MHK_BITMAP_COMPRESSED;

// File structures, turn on packing

#pragma pack(push, 1)
typedef struct {
  uint16_t width;
  uint16_t height;
  uint16_t bytes_per_row;
  uint8_t compression_flag;
  uint8_t truecolor_flag;
} MHK_BITMAP_header;
#pragma pack(pop)

// Byte order utilities
// f == file, n == native

static inline void MHK_BITMAP_header_fton(MHK_BITMAP_header* s) {
  s->width = OSSwapBigToHostInt16(s->width);
  s->height = OSSwapBigToHostInt16(s->height);
  s->bytes_per_row = OSSwapBigToHostInt16(s->bytes_per_row);
}

// decompression functions
bool read_raw_bgr_pixels(int fd, off_t offset, MHK_BITMAP_header* header, void* bgra_buffer);
bool read_raw_indexed_pixels(int fd, off_t offset, MHK_BITMAP_header* header, void* bgra_buffer);
bool read_compressed_indexed_pixels(int fd, off_t offset, MHK_BITMAP_header* header, void* bgra_buffer);
