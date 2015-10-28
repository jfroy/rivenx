// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include <atomic>

#include "Base/cxx_policies.h"
#include "Base/integer.h"
#include "Base/next_element_helper.h"

namespace rx {
namespace atomic {

// Linked-list atomic stack. Requires T to have a "next" element pointer, or to specialize the
// template functions in next_element_helper.h. The list uses a generation counter to avoid the ABA
// problem and relies on fast 16 bytes CAS operations on Intel and ARM for performance.
template <typename T>
class LinkStack : public noncopyable {
 public:
  using value_type = T;
  using reference = value_type&;
  using pointer = value_type*;

  // Estimated cache line size. If this is too large, it waste a bit of memory but shouldn't cause
  // additional cache line loads. If it is too small, it will potentially cause false sharing, i.e.
  // lower performance due to cache line sharing/trashing between cores/threads.
  static const int CACHE_LINE_SIZE = 64;

  LinkStack() {
    // Go through the non-atomic stack because during construction the stack is not shared.
    // Furthermore, whoever publishes the stack after construction to other threads will likely emit
    // a release barrier and those other threads will emit an acquire barrier, making those stores
    // visible.
    d_.s.head = nullptr;
    d_.s.generation = 0;
  }

  void push(reference element) noexcept {
    // Local stack representing the new head.
    Stack desired;

    // Set the element as the desired head.
    desired.head = &element;

    // Cache a reference to the element's next pointer. The next pointer will be modified through
    // that reference in the CAS loop.
    auto& next = NextElementPointer(element);

    // Relaxed load the stack head. This is done through the non-atomic alias because certain
    // architectures do not support 16 bytes atomic loads. We don't care about a torn or stale load
    // here because the CAS below will fail and then we'll retry with a fresh value. This is meant
    // to be a fast speculative load to maybe succeed the CAS on the first try.
    Stack expected{d_.s};

    // Set the element's next pointer to the current head and bump the generation counter. Retry
    // this in a loop until the CAS succeeds. The CAS emits a release barrier on success, and
    // otherwise relaxed loads the stack head (as above).
    do {
      next = expected.head;
      desired.generation = expected.generation + 1;
    } while (!d_.as.compare_exchange_weak(expected, desired, std::memory_order_release));
  }

  void push_range(reference head, reference tail) noexcept {
    // This method is the same as push but accepts a range of already-linked elements. See above for
    // implementation details.
    Stack desired;
    desired.head = &head;
    auto& next = NextElementPointer(tail);
    Stack expected{d_.s};
    do {
      next = expected.head;
      desired.generation = expected.generation + 1;
    } while (!d_.as.compare_exchange_weak(expected, desired, std::memory_order_release));
  }

  pointer try_pop() noexcept {
    // Acquire load the stack head. There is no valid optimization for this load because it has to
    // be atomic (no torn value
    Stack expected{d_.s};

    // If there is no head, return right away.
    if (!expected.head) {
      return nullptr;
    }

    // Set the stack head to the current head's next element and bump the generation counter. Retry
    // this in a loop until the CAS succeeds. The CAS emits a release barrier on success, and
    // otherwise loads with an acquire barrier the stack (as above).
    Stack desired;
    do {
      desired.head = NextElementPointer(expected.head);
      desired.generation = expected.generation + 1;
    } while (!d_.as.compare_exchange_weak(expected, desired, std::memory_order_acq_rel));

    // Set the next pointer on the element to null and return it.
    NextElementPointer(expected.head) = nullptr;
    return expected.head;
  }

  pointer try_pop_all() noexcept {
    // This method is the same as try_pop but returns the entire list of elements. See above for
    // implementation details.
    std::atomic_thread_fence(std::memory_order_acquire);
    Stack expected{d_.s};
    if (!expected.head) {
      return nullptr;
    }
    Stack desired;
    desired.head = nullptr;
    do {
      desired.generation = expected.generation + 1;
    } while (!d_.as.compare_exchange_weak(expected, desired, std::memory_order_acq_rel));
    return expected.head;
  }

 private:
  // The stack is represented by a head pointer and a pointer-sized generation counter. The
  // generation counter is used to avoid ABA corruption.
  struct Stack {
    pointer head;
    intptr_t generation;
  };

  // Store our data in cache line chunks aligned to cache line boundaries.
  struct alignas(CACHE_LINE_SIZE) CacheLineData {
    // Union to allow non-atomic access to the stack. See the push function for details.
    union {
      std::atomic<Stack> as;
      Stack s;
    };
  };

  CacheLineData d_;
};

}  //  namespace atomic
}  //  namespace rx
