// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include <libkern/OSByteOrder.h>

// Mohawk archives use big endian byte order

// Normal signatures
extern const char MHK_MHWK_signature[4];
extern const char MHK_RSRC_signature[4];

// Integer signatures
extern const uint32_t MHK_MHWK_signature_integer;
extern const uint32_t MHK_RSRC_signature_integer;

// File structures, turn on packing

#pragma pack(push, 1)
typedef struct {
  uint32_t signature;
  uint32_t content_length;
} MHK_chunk_header;

typedef struct {
  uint32_t signature;
  uint32_t rsrc_total_size;
  uint32_t total_archive_size;
  uint32_t rsrc_dir_absolute_offset;
  uint16_t file_table_rsrc_dir_offset;
  uint16_t total_file_table_size;
} MHK_RSRC_header;

typedef struct {
  uint16_t rsrc_name_list_rsrc_dir_offset;
  uint16_t count;
} MHK_type_table_header;

typedef struct {
  char name[4];
  uint16_t rsrc_table_rsrc_dir_offset;
  uint16_t name_table_rsrc_dir_offset;
} MHK_type_table_entry;

typedef struct { uint16_t count; } MHK_rsrc_table_header;

typedef struct {
  uint16_t id;
  uint16_t index;
} MHK_rsrc_table_entry;

typedef struct { uint16_t count; } MHK_name_table_header;

typedef struct {
  uint16_t name_list_offset;
  uint16_t index;
} MHK_name_table_entry;

typedef struct { uint32_t count; } MHK_file_table_header;

typedef struct {
  uint32_t absolute_offset;
  uint16_t size_low;
  uint8_t size_high;
  uint8_t flags;
  uint16_t unknown1;
} MHK_file_table_entry;
#pragma pack(pop)

// Byte order utilities
// f == file, n == native

static inline void MHK_chunk_header_fton(MHK_chunk_header* s) {
  s->content_length = OSSwapBigToHostInt32(s->content_length);
}

static inline void MHK_RSRC_header_fton(MHK_RSRC_header* s) {
  s->rsrc_total_size = OSSwapBigToHostInt32(s->rsrc_total_size);
  s->total_archive_size = OSSwapBigToHostInt32(s->total_archive_size);
  s->rsrc_dir_absolute_offset = OSSwapBigToHostInt32(s->rsrc_dir_absolute_offset);
  s->file_table_rsrc_dir_offset = OSSwapBigToHostInt16(s->file_table_rsrc_dir_offset);
  s->total_file_table_size = OSSwapBigToHostInt16(s->total_file_table_size);
}

static inline void MHK_type_table_header_fton(MHK_type_table_header* s) {
  s->rsrc_name_list_rsrc_dir_offset = OSSwapBigToHostInt16(s->rsrc_name_list_rsrc_dir_offset);
  s->count = OSSwapBigToHostInt16(s->count);
}

static inline void MHK_type_table_entry_fton(MHK_type_table_entry* s) {
  s->rsrc_table_rsrc_dir_offset = OSSwapBigToHostInt16(s->rsrc_table_rsrc_dir_offset);
  s->name_table_rsrc_dir_offset = OSSwapBigToHostInt16(s->name_table_rsrc_dir_offset);
}

static inline void MHK_rsrc_table_header_fton(MHK_rsrc_table_header* s) {
  s->count = OSSwapBigToHostInt16(s->count);
}

static inline void MHK_rsrc_table_entry_fton(MHK_rsrc_table_entry* s) {
  s->id = OSSwapBigToHostInt16(s->id);
  s->index = OSSwapBigToHostInt16(s->index);
}

static inline void MHK_name_table_header_fton(MHK_name_table_header* s) {
  s->count = OSSwapBigToHostInt16(s->count);
}

static inline void MHK_name_table_entry_fton(MHK_name_table_entry* s) {
  s->name_list_offset = OSSwapBigToHostInt16(s->name_list_offset);
  s->index = OSSwapBigToHostInt16(s->index);
}

static inline void MHK_file_table_header_fton(MHK_file_table_header* s) {
  s->count = OSSwapBigToHostInt32(s->count);
}

static inline void MHK_file_table_entry_fton(MHK_file_table_entry* s) {
  s->absolute_offset = OSSwapBigToHostInt32(s->absolute_offset);
  s->size_low = OSSwapBigToHostInt16(s->size_low);
  s->unknown1 = OSSwapBigToHostInt16(s->unknown1);
}
