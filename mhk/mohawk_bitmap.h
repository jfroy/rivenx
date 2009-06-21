/*
 *  mohawk_bitmap.h
 *  MHKKit
 *
 *  Created by Jean-Francois Roy on 23/06/2005.
 *  Copyright 2005 MacStorm. All rights reserved.
 *
 */

#if !defined(mohawk_bitmap_h)
#define mohawk_bitmap_h 1

#include <MHKKit/mohawk_core.h>

// Compression constants
extern const int MHK_BITMAP_PLAIN;
extern const int MHK_BITMAP_COMPRESSED;

// Buffer format constants
typedef enum {
    MHK_RGBA_UNSIGNED_BYTE_PACKED, 
    MHK_ARGB_UNSIGNED_BYTE_PACKED, 
    MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED
} MHK_BITMAP_FORMAT;

// File structures, turn on packing

#pragma pack(push, 1)
typedef struct {
    uint16_t width;
    uint16_t height;
    uint16_t bytes_per_row;
    unsigned char compression_flag;
    unsigned char truecolor_flag;
} MHK_BITMAP_header;
#pragma pack(pop)

// Byte order utilities
// f == file, n == native

MHK_INLINE void MHK_BITMAP_header_fton(MHK_BITMAP_header *s) {
    s->width = CFSwapInt16BigToHost(s->width);
    s->height = CFSwapInt16BigToHost(s->height);
    s->bytes_per_row = CFSwapInt16BigToHost(s->bytes_per_row);
}

// decompression functions
OSStatus read_raw_bgr_pixels(SInt16 fork_ref, SInt64 offset, MHK_BITMAP_header* header, void* pixels, MHK_BITMAP_FORMAT format);
OSStatus read_raw_indexed_pixels(SInt16 fork_ref, SInt64 offset, MHK_BITMAP_header* header, void* pixels, MHK_BITMAP_FORMAT format);
OSStatus read_compressed_indexed_pixels(SInt16 fork_ref, SInt64 offset, MHK_BITMAP_header* header, void* pixels, MHK_BITMAP_FORMAT format);

#endif // mohawk_bitmap_h
