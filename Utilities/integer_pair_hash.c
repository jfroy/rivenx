/*
 *  integer_pair_hash.c
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 30/12/2007.
 *  Copyright 2005-2010 MacStorm. All rights reserved.
 *
 */

#include "Utilities/integer_pair_hash.h"


size_t integer_pair_hash(int a, int b) {
    uint64_t key = ((uint64_t)a << 32) | (uint64_t)b;
    
    key = (~key) + (key << 18); // key = (key << 18) - key - 1;
    key = key ^ (key >> 31);
    key = key * 21; // key = (key + (key << 2)) + (key << 4);
    key = key ^ (key >> 11);
    key = key + (key << 6);
    key = key ^ (key >> 22);
    
    return (size_t)key;
}
