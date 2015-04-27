// Copyright 2015 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include "Base/cxx_policies.h"

#include <atomic>

namespace rx {

template <typename T>
class ref_counted : public noncopyable {
 protected:
  ~ref_counted() = default;

  void Retain() const { ref_count_.fetch_add(1, std::memory_order_relaxed); }
  bool Release() const {
    auto ref = ref_count_.fetch_sub(1, std::memory_order_relaxed);
    if (ref == 1) {
      std::atomic_thread_fence(std::memory_order_seq_cst);
      delete static_cast<const T*>(this);
    }
  }

 private:
  mutable std::atomic_uint_fast32_t ref_count_;
};

//! Smart pointer for ref-counted objects. Based on shared_ptr and chromium's scoped_refptr.
template <typename T>
class scoped_refptr {
 public:
  typedef T element_type;

  // constructors
  constexpr scoped_refptr() : ptr_(nullptr) {}

  explicit scoped_refptr(T* p) : ptr_(p) {
    if (ptr_) Retain(ptr_);
  }

  scoped_refptr(const scoped_refptr& r) : ptr_(r.ptr_) {
    if (ptr_) Retain(ptr_);
  }

  template <typename U>
  scoped_refptr(const scoped_refptr<U>& r)
      : ptr_(r.get()) {
    if (ptr_) Retain(ptr_);
  }

  scoped_refptr(scoped_refptr&& r) : ptr_(r.get()) { r.ptr_ = nullptr; }

  template <typename U>
  scoped_refptr(scoped_refptr<U>&& r)
      : ptr_(r.get()) {
    r.ptr_ = nullptr;
  }

  scoped_refptr(std::nullptr_t) : scoped_refptr() {}

  // destructor
  ~scoped_refptr() {
    if (ptr_) Release(ptr_);
  }

  // observers
  T* get() const { return ptr_; }

  T& operator*() const {
    debug_assert(ptr_);
    return *ptr_;
  }

  T* operator->() const {
    debug_assert(ptr_);
    return ptr_;
  }

  explicit operator bool() const { return ptr_ != nullptr; }

  // assignment
  scoped_refptr& operator=(const scoped_refptr& r) {
    shared_ptr(r).swap(*this);
    return *this;
  }

  template <typename U>
  scoped_refptr& operator=(const scoped_refptr<U>& r) {
    shared_ptr(r).swap(*this);
    return *this;
  }

  scoped_refptr& operator=(scoped_refptr&& r) {
    scoped_refptr(std::move(r)).swap(*this);
    return *this;
  }

  template <typename U>
  scoped_refptr& operator=(scoped_refptr<U>&& r) {
    scoped_refptr(std::move(r)).swap(*this);
    return *this;
  }

  // modifiers
  void swap(scoped_refptr& r) { std::swap(ptr_, r.ptr_); }

  void reset() { scoped_refptr().swap(*this); }

  template <typename U>
  void reset(U* p) {
    scoped_refptr(p).swap(*this);
  }

 protected:
  T* ptr_;

 private:
  static void Retain(T* p);
  static void Release(T* p);
};

// static
template <typename T>
void scoped_refptr<T>::Retain(T* p) {
  p->Retain();
}

// static
template <typename T>
void scoped_refptr<T>::Release(T* p) {
  p->Release();
}

// scoped_refptr specialized algorithms
template <typename T>
inline void swap(scoped_refptr<T>& x, scoped_refptr<T>& y) noexcept {
  x.swap(y);
}

}  // namespace rx
