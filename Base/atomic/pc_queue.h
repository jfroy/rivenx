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
// and must be resized before use. Resizing to 0 will deallocate all heap memory.
//
// The resize operation is not thread safe. The initial owner of the queue must resize it before
// publishing it to other threads. Similarly, destruction of the queue is not thread safe and must
// be performed by the last owner of the queue after it has been ensured that no other thread has
// access or makes use of the queue.
//
// By design, there can be only one consumer and one producer thread without locking. Any other
// configuration requires use of external serialization (with the producer and consumer sides being
// independent of each other).
//
// The queue always keeps one slot empty to avoid the "empty or full" confusion when the enqueue and
// dequeue pointers are equal. The effective capacity is therefore one less than requested.
template <typename T>
class FixedSinglePCQueue : public noncopyable {
 public:
  using value_type = T;
  using reference = value_type&;
  using pointer = value_type*;
  using range = std::pair<pointer, pointer>;
  using span = std::pair<range, range>;

  // Estimated cache line size. If this is too large, no problem. But if too big, it will lead to
  // false sharing and decreased performance.
  static constexpr size_t cache_line_size() { return 64; }

  FixedSinglePCQueue() = default;

  // Resize the queue to the specified capacity. No memory allocation will be performed beyond this
  // operation. Passing 0 will deallocate all memory. Not thread safe at all.
  void resize(size_t capacity) {
    buffer_.clear();
    buffer_.resize(capacity);

    enqueue_begin_ = std::begin(buffer_);
    enqueue_end_ = std::end(buffer_);
    enqueue_ptr_.store(enqueue_begin_, std::memory_order_relaxed);

    dequeue_begin_ = std::begin(buffer_);
    dequeue_end_ = std::end(buffer_);
    dequeue_ptr_.store(dequeue_begin_, std::memory_order_relaxed);
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

    // Calculate the number of slots available on the right and left of the enqueue pointer.
    // Generally speaking, the enqueue pointer cannot move forward past the dequeue pointer. Remove
    // one slot from the end of the range to avoid the "empty or full" state overlap.
    ssize_t right_avail;
    ssize_t left_avail;

    // Acquire-load the enqueue pointer and then load the dequeue pointer.
    auto local_enqueue_ptr = enqueue_ptr_.load(std::memory_order_acquire);
    auto local_dequeue_ptr = dequeue_ptr_.load(std::memory_order_relaxed);

    // If the enqueue pointer is on the left of the dequeue pointer (i.e. behind), there is space
    // available only on the right of the enqueue pointer (i.e. forward).
    if (local_enqueue_ptr < local_dequeue_ptr) {
      right_avail = local_dequeue_ptr - local_enqueue_ptr;
      left_avail = 0;
    }

    // Otherwise the enqueue pointer is on the right of the dequeue pointer (i.e. ahead) and there
    // is space both on the right of the enqueue pointer (i.e. forward) and on the left of the it
    // (i.e. behind).
    else {
      right_avail = enqueue_end_ - local_enqueue_ptr;
      left_avail = local_dequeue_ptr - enqueue_begin_;
    }

    // Remove one from the end of the range to keep one slot open (see above for explanation).
    if (right_avail > 0) {
      --right_avail;
    } else {
      --left_avail;
    }

    // If there is not enough space for all the elements, fail the entire operation.
    if (right_avail + left_avail < nelements) {
      return false;
    }

    // Copy elements from the input iterator starting with the right (i.e. forward) range.
    auto ncopy = std::min(right_avail, nelements);
    auto new_enqueue_ptr = std::copy_n(first, ncopy, local_enqueue_ptr);

    // Copy the remainder of the input (if any) in the left (i.e. behind) range.
    if (ncopy < nelements) {
      std::advance(first, ncopy);
      ncopy = nelements - ncopy;
      new_enqueue_ptr = std::copy_n(first, ncopy, enqueue_begin_);
    }

    // Publish new elements by Release-storing the new enqueue pointer.
    enqueue_ptr_.store(new_enqueue_ptr, std::memory_order_release);

    // All done.
    return true;
  }

 private:
  std::atomic<pointer> enqueue_ptr_{0};  // Owned (modified) by the producer. Read by all.
  pointer const enqueue_begin_{0};       // Copy of buffer start for producer.
  pointer const enqueue_end_{0};         // Copy of buffer end for producer.
  static_assert(sizeof(enqueue_ptr_) == sizeof(pointer), "atomic pointer size != pointer size");
  int8_t enqueue_cache_line_filler[cache_line_size() - (sizeof(pointer) * 3)];

  std::atomic<pointer> dequeue_ptr_{0};  // Owned (modified) by the consumer. Read by all.
  pointer const dequeue_begin_{0};       // Copy of buffer start for consumer.
  pointer const dequeue_end_{0};         // Copy of buffer end for consumer.

  std::vector<T> buffer_;  // Storage for elements.
};

}  //  namespace atomic
}  //  namespace rx
