// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include "Base/RXBufferMacros.h"

namespace rx {

template <typename T>
constexpr off_t NextElementPointerOffset() {
  return offsetof(T, next);
}

template <typename T>
T*& NextElementPointer(T* element) {
  return *reinterpret_cast<T**>(BUFFER_OFFSET(element, NextElementPointerOffset<T>()));
}

template <typename T>
T*& NextElementPointer(T& element) {
  return NextElementPointer(&element);
}

}  //  namespace rx
