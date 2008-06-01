/*
 *	mohawk_wave.h
 *	MHKKit
 *
 *	Created by Jean-Francois Roy on 09/04/2005.
 *	Copyright 2005 MacStorm. All rights reserved.
 *
 */

#if !defined(mohawk_wave_h)
#define mohawk_wave_h 1

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

#pragma options align=packed
typedef struct {
	uint16_t sampling_rate;
	uint32_t frame_count;
	unsigned char bit_depth;
	unsigned char channel_count;
	uint16_t compression_type;
	unsigned char reserved[10];
} MHK_WAVE_Data_chunk_header;
#pragma options align=reset

// Byte order utilities
// f == file, n == native

MHK_INLINE void MHK_WAVE_Data_chunk_header_fton(MHK_WAVE_Data_chunk_header *s) {
	s->sampling_rate = CFSwapInt16BigToHost(s->sampling_rate);
	s->frame_count = CFSwapInt32BigToHost(s->frame_count);
	s->compression_type = CFSwapInt16BigToHost(s->compression_type);
}

#endif // mohawk_wave_h
