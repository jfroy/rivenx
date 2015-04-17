// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include <atomic>
#include <iterator>
#include <type_traits>
#include <utility>
#include <vector>

#include "Base/cxx_policies.h"

namespace rx {
namespace atomic {

// Single producer-consumer queue backed by a fixed-size memory allocation.
//
// The queue allows a range of elements to be enqueued and all elements to be dequeued in one
// operation to allow efficient batch processing. The model is transactional: if the operation fails
// (for example if there is not enough memory), there will be no observable change to the queue.
//
// The queue never allocates memory in enqueue or dequeue operations. It initially has no capacity
// and must be resized before use. Resizing to 0 will deallocate all heap memory. An extra element
// is allocated to avoid the "empty or full" state overlap (equal enqueue and dequeue pointers) by
// always keeping one slot empty.
//
// The resize operation is not thread safe. The initial owner of the queue must resize it before
// publishing it to other threads. Similarly, destruction of the queue is not thread safe and must
// be performed by the last owner of the queue after it has been ensured that no other thread has
// access or makes use of the queue.
//
// By design, there can be only one consumer and one producer thread without locking. Any other
// configuration requires use of external serialization (with the producer and consumer sides being
// independent of each other).
template <typename T>
class FixedSinglePCQueue : public noncopyable {
 public:
  using value_type = T;
  using reference = value_type&;
  using pointer = value_type*;
  using range = std::pair<pointer, pointer>;
  using range_pair = std::pair<range, range>;
  using size_pair = std::pair<ssize_t, ssize_t>;

  // Estimated cache line size. If this is too large, no problem. But if too big, it will lead to
  // false sharing and decreased performance.
  static const int CACHE_LINE_SIZE = 64;

  FixedSinglePCQueue() = default;

  // Resize the queue to the specified capacity. No memory allocation will be performed beyond this
  // operation. Passing 0 will deallocate all memory. Not thread safe at all.
  void resize(size_t capacity) {
    pointer begin, end;

    buffer_.clear();
    if (capacity > 0) {
      buffer_.resize(capacity + 1);
      begin = &buffer_.front();
      end = &buffer_.back() + 1;
    } else {
      buffer_.shrink_to_fit();
      begin = nullptr;
      end = nullptr;
    }

    enqueue_.ptr.store(begin, std::memory_order_relaxed);
    enqueue_.other_ptr_cache = begin;
    const_cast<pointer&>(enqueue_.begin) = begin;
    const_cast<pointer&>(enqueue_.end) = end;

    dequeue_.ptr.store(begin, std::memory_order_relaxed);
    dequeue_.other_ptr_cache = begin;
    const_cast<pointer&>(dequeue_.begin) = begin;
    const_cast<pointer&>(dequeue_.end) = end;

    std::atomic_thread_fence(std::memory_order_seq_cst);
  }

  // Try to enqueue the element. Returns false if the operation can't be completed (for example if
  // there is not enough space).
  bool try_enqueue(T const& element) {
    // FIXME: optimize single element enqueue by replacing the range calculation and copy path.
    return try_enqueue(&element, 1);
  }

  // Try to enqueue elements in the range [first, last). Returns false if the operation can't be
  // completed (for example if there is not enough space). Partial transactions are not attempted,
  // this is all or nothing. If at all possible, use an iterator type that has good std::distance
  // and forward iteration performance.
  template <typename Iter>
  bool try_enqueue(Iter first, Iter last) {
    return try_enqueue(first, std::distance(first, last));
  }

  // Try to enqueue elements in the range [first, first + nelements). Returns false if the operation
  // can't be completed (for example if there is not enough space). Partial transactions are not
  // attempted, this is all or nothing. If at all possible, use an iterator type that has good
  // forward iteration performance.
  template <typename Iter>
  bool try_enqueue(Iter first, ssize_t nelements) {
    // Return true in the degenerate 0 case.
    if (nelements == 0) {
      return true;
    }

    // Calculate the number of available elements on the right and left of the enqueue pointer.
    // Generally speaking, the enqueue pointer cannot move forward past the dequeue pointer. Remove
    // one slot from the end of the range to avoid the "empty or full" state overlap.
    pointer enqueue_ptr;
    auto available = right_left_available_weak(enqueue_, enqueue_ptr);

    // If there is not enough space for all the elements, update the other pointer by loading from
    // the dequeue cache line and calculate again.
    if (available.first + available.second < nelements + 1) {
      enqueue_.other_ptr_cache = dequeue_.ptr.load(std::memory_order_relaxed);
      available = right_left_available_weak(enqueue_, enqueue_ptr);
    }

    // If there is still not enough space, fail the entire transaction.
    if (available.first + available.second < nelements + 1) {
      return false;
    }

    // Acquire fence. Prevents memory operations from being reordered above it.
    std::atomic_thread_fence(std::memory_order_acquire);

    // Copy elements from the input iterator starting with the right (i.e. forward) range.
    auto ncopy = std::min(available.first, nelements);
    pointer new_enqueue_ptr = std::copy_n(first, ncopy, enqueue_ptr);

    // Copy the remainder of the input (if any) in the left (i.e. behind) range.
    if (ncopy < nelements) {
      std::advance(first, ncopy);
      ncopy = nelements - ncopy;
      new_enqueue_ptr = std::copy_n(first, ncopy, enqueue_.begin);
    }

    // Prevent all preceding memory operations from being reordered past subsequent writes.
    std::atomic_thread_fence(std::memory_order_release);

    // Publish the new enqueue pointer.
    enqueue_.ptr.store(new_enqueue_ptr, std::memory_order_relaxed);

    // All done.
    return true;
  }

  // Return the range of elements that can be dequeued. First only looks at the dequeue cache line.
  // If the range is empty, the enqueue cache line is read. Does not update the dequeue cache line
  // (i.e. does not consume the elements).
  const range_pair& dequeue_peek() {
    // Calculate the number of available elements on the right and left of the dequeue pointer.
    // Generally speaking, the dequeue pointer cannot move forward past the enqueue pointer.
    size_pair available;

    // If the pointers are equal, it indicates an empty dequeue range. Try to update the other
    // pointer by loading from the enqueue cache line and calculate again.
    pointer dequeue_ptr = dequeue_.ptr.load(std::memory_order_relaxed);
    if (dequeue_ptr == dequeue_.other_ptr_cache) {
      dequeue_.other_ptr_cache = enqueue_.ptr.load(std::memory_order_relaxed);
      if (dequeue_ptr == dequeue_.other_ptr_cache) {
        available = {0, 0};
      } else {
        available = right_left_available_weak(dequeue_, dequeue_ptr);
      }
    } else {
      available = right_left_available_weak(dequeue_, dequeue_ptr);
    }

    // Update the dequeue range_pair.
    dequeue_.dequeue_rp.first = {dequeue_ptr, dequeue_ptr + available.first};
    if (available.second == 0) {
      dequeue_.dequeue_rp.second = {nullptr, nullptr};
    } else {
      dequeue_.dequeue_rp.second = {dequeue_.begin, dequeue_.begin + available.second};
    }

    // Acquire fence. Prevents memory operations from being reordered above it.
    std::atomic_thread_fence(std::memory_order_acquire);

    // Return a reference to the range_pair.
    return dequeue_.dequeue_rp;
  }

  // Consume the last range_pair returned by dequeue_peek and update the dequeue cache line.
  void dequeue_consume() {
    pointer new_dequeue_ptr = (dequeue_.dequeue_rp.second.second)
                                  ? dequeue_.dequeue_rp.second.second
                                  : dequeue_.dequeue_rp.first.second;

    // Prevent all preceding memory operations from being reordered past subsequent writes.
    std::atomic_thread_fence(std::memory_order_release);

    // Publish the new dequeue pointer.
    dequeue_.ptr.store(new_dequeue_ptr, std::memory_order_relaxed);
  }

 private:
  struct alignas(CACHE_LINE_SIZE) CacheLineData {
    std::atomic<pointer> ptr{0};  // Atomic access pointer.
    pointer other_ptr_cache{0};   // Local cache of the other access pointer.
    pointer const begin{0};       // Cache of buffer start.
    pointer const end{0};         // Cache of buffer end.
    range_pair dequeue_rp;        // Last dequeue range_pair. Only used by consumer.
  };
  static_assert(sizeof(CacheLineData) == CACHE_LINE_SIZE, "CacheLineData size != CACHE_LINE_SIZE");

  // Calculate the space available on the right (pair.first) and left (pair.second) of the specified
  // cache line's owned pointer (i.e. either the enqueue or dequeue pointer). Also return by
  // reference the owned pointer (to avoid multiple atomic loads). Can remove one from the end of
  // the range if requested (used for enqueue to avoid "empty or full" state overlap). The function
  // uses the cache line's copy of the other cache line's owned pointer for the calculation.
  size_pair right_left_available_weak(const CacheLineData& cld, pointer& out_ptr) {
    size_pair available;

    // Load the pointer and cache of the other pointer without ordering.
    out_ptr = cld.ptr.load(std::memory_order_relaxed);
    auto other_ptr = cld.other_ptr_cache;

    // If the pointer is on the left of the other pointer (i.e. behind), there is space available
    // only on the right of the pointer (i.e. forward).
    if (out_ptr < other_ptr) {
      available.first = other_ptr - out_ptr;
      available.second = 0;
    }

    // Otherwise the pointer is on the right of the other pointer (i.e. ahead) or equal and there
    // is space both on the right (i.e. forward) and on the left of it (i.e. behind).
    else {
      available.first = cld.end - out_ptr;
      available.second = other_ptr - cld.begin;
    }

    return available;
  }

  CacheLineData enqueue_;  // Enqueue (producer) cache line.
  CacheLineData dequeue_;  // Dequeue (consumer) cache line.

  std::vector<T> buffer_;  // Storage for elements.
};

}  //  namespace atomic
}  //  namespace rx
