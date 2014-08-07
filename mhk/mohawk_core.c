// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#include "mhk/mohawk_core.h"

#include "mhk/mohawk_bitmap.h"
#include "mhk/mohawk_sound.h"

const char MHK_MHWK_signature[4] = {'M', 'H', 'W', 'K'};
const char MHK_RSRC_signature[4] = {'R', 'S', 'R', 'C'};

const char MHK_WAVE_signature[4] = {'W', 'A', 'V', 'E'};
const char MHK_Cue_signature[4] = {'C', 'u', 'e', '#'};
const char MHK_ADPC_signature[4] = {'A', 'D', 'P', 'C'};
const char MHK_Data_signature[4] = {'D', 'a', 't', 'a'};

const int MHK_WAVE_ADPCM = 1;
const int MHK_WAVE_MP2 = 2;

const int MHK_BITMAP_RAW = 0;
const int MHK_BITMAP_COMPRESSED = 4;

#if defined(__BIG_ENDIAN__)
const uint32_t MHK_MHWK_signature_integer = 'MHWK';
const uint32_t MHK_RSRC_signature_integer = 'RSRC';

const uint32_t MHK_WAVE_signature_integer = 'WAVE';
const uint32_t MHK_Cue_signature_integer = 'Cue#';
const uint32_t MHK_ADPC_signature_integer = 'ADPC';
const uint32_t MHK_Data_signature_integer = 'Data';
#else
const uint32_t MHK_MHWK_signature_integer = 'KWHM';
const uint32_t MHK_RSRC_signature_integer = 'CRSR';

const uint32_t MHK_WAVE_signature_integer = 'EVAW';
const uint32_t MHK_Cue_signature_integer = '#euC';
const uint32_t MHK_ADPC_signature_integer = 'CPDA';
const uint32_t MHK_Data_signature_integer = 'ataD';
#endif
