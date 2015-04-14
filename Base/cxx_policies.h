// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include "Base/RXBase.h"

namespace rx {

//! Inherit this type to disallow copying the derived type.
struct noncopyable {
  noncopyable() = default;
  noncopyable(noncopyable const& rhs) = delete;
  noncopyable& operator=(noncopyable const& rhs) = delete;
};

}  // namespace rx {
