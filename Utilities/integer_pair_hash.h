/*
 *  integer_pair_hash.h
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 30/12/2007.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#ifndef INTEGER_PAIR_HASH_H
#define INTEGER_PAIR_HASH_H

#include <stdlib.h>

static inline uint32_t hash_int32(uint32_t key)
{
  key = ~key + (key << 15); // key = (key << 15) - key - 1;
  key = key ^ (key >> 12);
  key = key + (key << 2);
  key = key ^ (key >> 4);
  key = key * 2057; // key = (key + (key << 3)) + (key << 11);
  key = key ^ (key >> 16);
  return key;
}

static inline uint64_t hash_int64(uint64_t key)
{
  key = (~key) + (key << 21); // key = (key << 21) - key - 1;
  key = key ^ (key >> 24);
  key = (key + (key << 3)) + (key << 8); // key * 265
  key = key ^ (key >> 14);
  key = (key + (key << 2)) + (key << 4); // key * 21
  key = key ^ (key >> 28);
  key = key + (key << 31);
  return key;
}

static inline uintptr_t hash_intptr(uintptr_t key)
{
#if __LP64__
  return hash_int64(key);
#else
  return hash_int32(key);
#endif
}

static inline uint32_t hash32_int64(uint64_t key)
{
  key = (~key) + (key << 18); // key = (key << 18) - key - 1;
  key = key ^ (key >> 31);
  key = key * 21; // key = (key + (key << 2)) + (key << 4);
  key = key ^ (key >> 11);
  key = key + (key << 6);
  key = key ^ (key >> 22);
  return (int)key;
}

static inline uintptr_t hash_combine(uintptr_t seed, uintptr_t key)
{
#if __LP64__
  seed ^= hash_int64(key) + 0x9e3779b9 + (seed << 6) + (seed >> 2);
#else
  seed ^= hash_int32(key) + 0x9e3779b9 + (seed << 6) + (seed >> 2);
#endif
  return seed;
}

#endif // INTEGER_PAIR_HASH_H
