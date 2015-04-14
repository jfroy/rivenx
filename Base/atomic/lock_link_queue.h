// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include <libkern/OSAtomic.h>

#include "Base/cxx_policies.h"
#include "Base/next_element_helper.h"

namespace rx {
namespace atomic {

template <typename T>
class LockLinkQueue : public noncopyable {
 public:
  using value_type = T;
  using reference = value_type&;
  using pointer = value_type*;

  static constexpr off_t next_pointer_offset = NextElementPointerOffset<value_type>();

  void Push(reference element) noexcept {
    OSAtomicFifoEnqueue(&head_, &element, next_pointer_offset);
  }

  pointer TryPop() noexcept {
    return reinterpret_cast<pointer>(OSAtomicFifoDequeue(&head_, next_pointer_offset));
  }

 private:
  OSFifoQueueHead head_ OS_ATOMIC_FIFO_QUEUE_INIT;
};

}  //  namespace atomic
}  //  namespace rx
