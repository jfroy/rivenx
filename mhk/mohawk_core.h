/*
 *  mohawk_core.h
 *  MHKKit
 *
 *  Created by Jean-Francois Roy on 09/04/2005.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#if !defined(mohawk_core_h)
#define mohawk_core_h 1

#include <CoreFoundation/CFByteOrder.h>

#if !defined(MHK_INLINE)
#define MHK_INLINE static __inline__
#endif

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

typedef struct {
  uint16_t count;
} MHK_rsrc_table_header;

typedef struct {
  uint16_t id;
  uint16_t index;
} MHK_rsrc_table_entry;

typedef struct {
  uint16_t count;
} MHK_name_table_header;

typedef struct {
  uint16_t name_list_offset;
  uint16_t index;
} MHK_name_table_entry;

typedef struct {
  uint32_t count;
} MHK_file_table_header;

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

MHK_INLINE void MHK_chunk_header_fton(MHK_chunk_header* s) { s->content_length = CFSwapInt32BigToHost(s->content_length); }

MHK_INLINE void MHK_RSRC_header_fton(MHK_RSRC_header* s)
{
  s->rsrc_total_size = CFSwapInt32BigToHost(s->rsrc_total_size);
  s->total_archive_size = CFSwapInt32BigToHost(s->total_archive_size);
  s->rsrc_dir_absolute_offset = CFSwapInt32BigToHost(s->rsrc_dir_absolute_offset);
  s->file_table_rsrc_dir_offset = CFSwapInt16BigToHost(s->file_table_rsrc_dir_offset);
  s->total_file_table_size = CFSwapInt16BigToHost(s->total_file_table_size);
}

MHK_INLINE void MHK_type_table_header_fton(MHK_type_table_header* s)
{
  s->rsrc_name_list_rsrc_dir_offset = CFSwapInt16BigToHost(s->rsrc_name_list_rsrc_dir_offset);
  s->count = CFSwapInt16BigToHost(s->count);
}

MHK_INLINE void MHK_type_table_entry_fton(MHK_type_table_entry* s)
{
  s->rsrc_table_rsrc_dir_offset = CFSwapInt16BigToHost(s->rsrc_table_rsrc_dir_offset);
  s->name_table_rsrc_dir_offset = CFSwapInt16BigToHost(s->name_table_rsrc_dir_offset);
}

MHK_INLINE void MHK_rsrc_table_header_fton(MHK_rsrc_table_header* s) { s->count = CFSwapInt16BigToHost(s->count); }

MHK_INLINE void MHK_rsrc_table_entry_fton(MHK_rsrc_table_entry* s)
{
  s->id = CFSwapInt16BigToHost(s->id);
  s->index = CFSwapInt16BigToHost(s->index);
}

MHK_INLINE void MHK_name_table_header_fton(MHK_name_table_header* s) { s->count = CFSwapInt16BigToHost(s->count); }

MHK_INLINE void MHK_name_table_entry_fton(MHK_name_table_entry* s)
{
  s->name_list_offset = CFSwapInt16BigToHost(s->name_list_offset);
  s->index = CFSwapInt16BigToHost(s->index);
}

MHK_INLINE void MHK_file_table_header_fton(MHK_file_table_header* s) { s->count = CFSwapInt32BigToHost(s->count); }

MHK_INLINE void MHK_file_table_entry_fton(MHK_file_table_entry* s)
{
  s->absolute_offset = CFSwapInt32BigToHost(s->absolute_offset);
  s->size_low = CFSwapInt16BigToHost(s->size_low);
  s->unknown1 = CFSwapInt16BigToHost(s->unknown1);
}

#endif // mohawk_core_h
