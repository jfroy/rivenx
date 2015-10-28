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
class SPCQueue : public noncopyable {
 public:
  using value_type = T;
  using reference = value_type&;
  using const_reference = const value_type&;
  using pointer = value_type*;
  using const_pointer = const value_type*;

 private:
  // Structure to store a begin and an end pointer.
  struct range {
    pointer begin;
    pointer end;

    ptrdiff_t size() const { return end - begin; }
  };

  // Structure to store a right-side and a left-ride range.
  struct range_pair {
    range right;
    range left;

    ptrdiff_t size() const { return right.size() + left.size(); }
  };

 public:
  // ITERATOR

  // Iterator over a queue range pair.
  class iterator : public std::iterator<std::random_access_iterator_tag, T> {
   public:
    using value_type = typename std::iterator<std::random_access_iterator_tag, T>::value_type;
    using difference_type =
        typename std::iterator<std::random_access_iterator_tag, T>::difference_type;
    using pointer = typename std::iterator<std::random_access_iterator_tag, T>::pointer;
    using reference = typename std::iterator<std::random_access_iterator_tag, T>::reference;

    iterator() = default;
    iterator(const iterator& rhs) = default;
    iterator& operator=(const iterator& rhs) = default;

    iterator(const range_pair& rp, pointer p) : rp_(&rp), p_(p) {}

    reference operator*() const { return *p_; }
    pointer operator->() const { return p_; }

    bool operator==(const iterator& rhs) const { return p_ == rhs.p_; }
    bool operator!=(const iterator& rhs) const { return p_ != rhs.p_; }
    bool operator<(const iterator& rhs) const { return *this - rhs < 0; }
    bool operator>(const iterator& rhs) const { return *this - rhs > 0; }
    bool operator<=(const iterator& rhs) const { return *this - rhs <= 0; }
    bool operator>=(const iterator& rhs) const { return *this - rhs >= 0; }

    iterator& operator+=(difference_type m) {
      auto p = p_ + m;
      if (p_ >= rp_->right.begin) {
        auto end_distance = p - rp_->right.end;
        if (end_distance >= 0) {
          p_ = rp_->left.begin + end_distance;
        } else {
          p_ = p;
        }
      } else {
        auto begin_distance = p - rp_->left.begin;
        if (begin_distance < 0) {
          p_ = rp_->right.end + begin_distance;
        } else {
          p_ = p;
        }
      }
      return *this;
    }

    iterator& operator-=(difference_type n) { return * this += -n; }
    iterator& operator++() { return * this += 1; }
    iterator& operator--() { return * this -= 1; }

    iterator operator++(int) {
      iterator tmp(*this);
      operator++();
      return tmp;
    }

    iterator operator--(int) {
      iterator tmp(*this);
      operator--();
      return tmp;
    }

    difference_type operator-(const iterator& rhs) {
      debug_assert(rp_ == rhs.rp_);
      if (rp_ == nullptr) {
        debug_assert(p_ == nullptr);
        debug_assert(rhs.p_ == nullptr);
        return 0;
      }
      if (p_ >= rp_->right.begin) {
        if (rhs.p_ >= rp_->right.begin) {
          return p_ - rhs.p_;
        } else {
          return -((rp_->right.end - p_) + (rhs.p_ - rp_->left.begin));
        }
      } else {
        if (rhs.p_ >= rp_->right.begin) {
          return (rp_->right.end - rhs.p_) + (p_ - rp_->left.begin);
        } else {
          return p_ - rhs.p_;
        }
      }
    }

    reference operator[](difference_type n) { return *(*this + n); }

    friend iterator operator+(iterator lhs, difference_type rhs) {
      lhs += rhs;
      return lhs;
    }

    friend iterator operator+(difference_type lhs, iterator rhs) {
      rhs += lhs;
      return rhs;
    }

    friend iterator operator-(iterator lhs, difference_type rhs) {
      lhs -= rhs;
      return lhs;
    }

    friend iterator operator-(difference_type lhs, iterator rhs) {
      rhs -= lhs;
      return rhs;
    }

    friend void swap(iterator& lhs, iterator& rhs) {
      auto tmp(std::move(lhs));
      lhs = std::move(rhs);
      rhs = std::move(tmp);
    }

   private:
    friend class SPCQueue;

    range_pair const* const rp_{nullptr};
    pointer p_{nullptr};
  };

  // An AccessView object creates begin and end iterators for the queue, either over the enqueue
  // or dequeue range.
  class AccessView {
   public:
    AccessView() = default;
    AccessView(const AccessView& rhs) = default;
    AccessView& operator=(const AccessView& rhs) = default;

    AccessView(const range_pair& rp) : rp_(&rp) {}

    iterator begin() {
      if (rp_) {
        return iterator(*rp_, rp_->right.begin);
      } else {
        return iterator();
      }
    }
    iterator end() {
      if (rp_) {
        return iterator(*rp_, rp_->left.end);
      } else {
        return iterator();
      }
    }

   private:
    const range_pair* rp_{nullptr};
  };

  // INIT

  SPCQueue() = default;
  ~SPCQueue() { Resize(0); }

  // Resizes the queue to the specified capacity. Passing 0 will free all heap memory. The Resize
  // function must only be called when only one core and thread has a reference to the queue. The
  // queue does not allocate memory from other functions.
  void Resize(size_t capacity) {
    // Emit acquire fence to see all previous writes.
    std::atomic_thread_fence(std::memory_order_acquire);

    if (buffer_) {
      // Consume every object. DequeueAccessView and Consume twice to force cached pointer updates.
      auto dav = DequeueAccessView();
      Consume(std::begin(dav), std::end(dav));
      dav = DequeueAccessView();
      Consume(std::begin(dav), std::end(dav));

      // Free the element buffer.
      free(buffer_);
      buffer_ = nullptr;
    }

    // Allocate new element buffer (if capacity > 0).
    pointer begin = nullptr;
    pointer end = nullptr;
    if (capacity > 0) {
      size_t bsize = sizeof(value_type) * (capacity + 1);
      buffer_ = static_cast<char*>(malloc(bsize));
      debug_assert(reinterpret_cast<uintptr_t>(buffer_) % alignof(value_type) == 0);
      begin = reinterpret_cast<pointer>(buffer_);
      end = reinterpret_cast<pointer>(buffer_ + bsize);
    }

    // Update the enqueue and dequeue cache lines.
    enqueue_.ptr.store(begin, std::memory_order_relaxed);
    enqueue_.rp = {{begin, begin}, {begin, begin}};
    const_cast<range&>(enqueue_.buffer_range) = {begin, end};

    dequeue_.ptr.store(begin, std::memory_order_relaxed);
    dequeue_.rp = {{begin, begin}, {begin, begin}};
    const_cast<range&>(dequeue_.buffer_range) = {begin, end};

    // Emit release fence to publish all previous writes.
    std::atomic_thread_fence(std::memory_order_release);
  }

  // ENQUEUE

  // Try to enqueue the element. Returns false if the operation can't be completed.
  bool TryEnqueue(T const& element) {
    // FIXME: optimize single element enqueue by replacing the range calculation and copy path.
    return TryEnqueue(&element, 1);
  }

  // Try to enqueue the element. Returns false if the operation can't be completed.
  bool TryEnqueue(T&& element) {
    // FIXME: optimize single element enqueue by replacing the range calculation and copy path.
    return TryEnqueue(std::make_move_iterator(&element), 1);
  }

  // Try to enqueue elements in the range [first, last). Returns false if the operation can't be
  // completed. Partial transactions are not attempted; this is all or nothing. The element
  // iterators must meet the requirements of ForwardIterator.
  template <typename ForwardIt>
  bool TryEnqueue(ForwardIt first, ForwardIt last) {
    return TryEnqueue(first, std::distance(first, last));
  }

  // Try to enqueue elements in the range [iter, iter + nelements). Returns false if the operation
  // can't be completed. Partial transactions are not attempted; this is all or nothing. The element
  // iterator must meet the requirements of ForwardIterator.
  template <typename ForwardIt>
  bool TryEnqueue(ForwardIt iter, ssize_t nelements) {
    // Return true in the degenerate 0 case.
    if (nelements == 0) {
      return true;
    }

    // Update the cache line's access range pair. This doesn't emit a fence.
    UpdateCacheLineRangePair(enqueue_);

    // If there is not enough space for all the elements, update the cache of the other access
    // pointer and update the access range pair again.
    //
    // Note that nelements + 1 is used to maintain an unused slot to distinguish an empty queue from
    // a full queue (i.e. remove ambiguitiy when the read and write pointers are equal).
    if (enqueue_.rp.size() < nelements + 1) {
      enqueue_.rp.left.end = dequeue_.ptr.load(std::memory_order_relaxed);
      UpdateCacheLineRangePair(enqueue_);
    }

    // If there is still not enough space, fail the entire transaction.
    if (enqueue_.rp.size() < nelements + 1) {
      return false;
    }

    // Emit an acquire fence. Prevents memory operations from being reordered above it and makes all
    // memory writes before a previously emitted release fence visible.
    std::atomic_thread_fence(std::memory_order_acquire);

    // Copy elements from the input iterator starting with the right (i.e. forward) range.
    auto ncopy = std::min(enqueue_.rp.right.size(), nelements);
    pointer new_enqueue_ptr = std::uninitialized_copy_n(iter, ncopy, enqueue_.rp.right.begin);

    // Copy the remainder of the input (if any) in the left (i.e. behind) range.
    if (ncopy < nelements) {
      std::advance(iter, ncopy);
      ncopy = nelements - ncopy;
      new_enqueue_ptr = std::uninitialized_copy_n(iter, ncopy, enqueue_.rp.left.begin);
    }

    // Emit a release barrier. Prevents memory operations from being reordered below it and
    // publishes memory writes to future acquire fences.
    std::atomic_thread_fence(std::memory_order_release);

    // Publish the new enqueue pointer without a fence. This write will eventually be visible by all
    // cores and only after the previous writes because of the release fence.
    enqueue_.ptr.store(new_enqueue_ptr, std::memory_order_relaxed);

    return true;
  }

  // DEQUEUE

  // Creates an AccessView object that provides an interator range over all elements in the queue.
  // Invalidates all prior dequeue access views and all iterators created from those access views.
  // Does not consume the elements from the queue.
  AccessView DequeueAccessView() {
    // Update the cache line's access range pair. This doesn't emit a fence.
    UpdateCacheLineRangePair(dequeue_);

    // If right.begin == left.end are equal, the queue may be empty. Update the cache of the other
    // access pointer and update the access range pair again.
    //
    // Note that rp.size() will return the full queue size when the pointers are equal, but the
    // implementation disambiguates this case as an empty queue.
    if (dequeue_.rp.right.begin == dequeue_.rp.left.end) {
      dequeue_.rp.left.end = enqueue_.ptr.load(std::memory_order_relaxed);
      UpdateCacheLineRangePair(dequeue_);
    }

    // If the pointers are still equal, the queue is empty. Return a dummy access view.
    if (dequeue_.rp.right.begin == dequeue_.rp.left.end) {
      return AccessView();
    }

    // Emit an acquire fence. Prevents memory operations from being reordered above it and makes all
    // memory writes before a previously emitted release fence visible.
    std::atomic_thread_fence(std::memory_order_acquire);

    // Return an access view for the dequeue range pair.
    return AccessView(dequeue_.rp);
  }

  // Consumes elements [first, last) from the queue. The iterators must be valid, which implies they
  // must have been created from a valid dequeue access view. Invalidates all dequeue access views
  // and all iterators created from those access views.
  void Consume(iterator first, iterator last) {
    // Exit early if the iterators are equal (empty range). This also handles null iterators
    // obtained from a default-initialized access view (which is returned by DequeueAccessView when
    // the queue is empty).
    if (first == last) {
      return;
    }

    debug_assert(first.rp_ == &dequeue_.rp);
    debug_assert(last.rp_ == &dequeue_.rp);

    // Destroy the elements in the range.
    for (; first != last; ++first) {
      first->~value_type();
    }

    // Prevent all preceding memory operations from being reordered past subsequent writes.
    std::atomic_thread_fence(std::memory_order_release);

    // Publish the new dequeue pointer without a fence. This write will eventually be visible by all
    // cores and only after the previous writes because of the release fence.
    dequeue_.ptr.store(&*last, std::memory_order_relaxed);
  }

 private:
  // Estimated cache line size. If this is too large, no problem. But if too big, it will lead to
  // false sharing and decreased performance.
  static const int CACHE_LINE_SIZE = 64;

  struct alignas(CACHE_LINE_SIZE) CacheLineData {
    // Atomic access pointer.
    std::atomic<pointer> ptr{nullptr};
    // Range pair for ptr. right.begin caches ptr. left.end caches the other access pointer.
    range_pair rp{{nullptr, nullptr}, {nullptr, nullptr}};
    // Range for the queue's buffer.
    const range buffer_range{nullptr, nullptr};
  };
  static_assert(sizeof(CacheLineData) == CACHE_LINE_SIZE, "CacheLineData size != CACHE_LINE_SIZE");

  // Updates the range pair of the specified cache line. Uses the cache line's copy of the other
  // cache line's owned pointer for the calculation.
  void UpdateCacheLineRangePair(CacheLineData& cld) {
    // Load the access pointer into the access range pair without emitting a fence.
    cld.rp.right.begin = cld.ptr.load(std::memory_order_relaxed);

    // If the access pointer is on the left of the other access pointer (i.e. behind), there is
    // space available only on the right of the pointer (i.e. forward).
    if (cld.rp.right.begin < cld.rp.left.end) {
      cld.rp.right.end = cld.rp.left.end;
      cld.rp.left.begin = cld.rp.left.end;
    }

    // Otherwise the access pointer is on the right of the other access pointer (i.e. ahead) or is
    // equal and there is space both on the right and on the left of it.
    else {
      cld.rp.right.end = cld.buffer_range.end;
      cld.rp.left.begin = cld.buffer_range.begin;
    }
  }

  CacheLineData enqueue_;  // Enqueue (producer) cache line.
  CacheLineData dequeue_;  // Dequeue (consumer) cache line.

  char* buffer_{nullptr};  // Storage for elements.
};

}  //  namespace atomic
}  //  namespace rx
