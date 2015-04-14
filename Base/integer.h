// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include <cstdint>

namespace rx {

template <size_t N>
struct Integer;

template <>
struct Integer<1> {
  using type = int8_t;
};

template <>
struct Integer<2> {
  using type = int16_t;
};

template <>
struct Integer<4> {
  using type = int32_t;
};

template <>
struct Integer<8> {
  using type = int64_t;
};

template <>
struct Integer<16> {
  using type = __int128;
};

}  //  namespace rx
