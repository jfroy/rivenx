// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include "Base/atomic/link_stack.h"
#include "Base/cxx_policies.h"

namespace rx {
namespace atomic {

template <typename T, size_t Capacity>
class LinkQueue : public noncopyable {
 public:
  using value_type = T;
  using reference = value_type&;
  using pointer = value_type*;

  LinkQueue() = default;

  void push(reference element) noexcept { write_stack_.push(element); }

  pointer try_pop() noexcept {
    auto read_head = read_stack_.try_pop();
    if (read_head) {
      return read_head;
    }
    auto write_head = write_stack_.try_pop_all();
    if (!write_head) {
      return nullptr;
    }
    auto last = write_head;
    while (write_head) {
      auto next_write_head = NextElementPointer(write_head);
      NextElementPointer(write_head) = read_head;
      read_head = write_head;
      write_head = next_write_head;
    }
    if (read_head != last) {
      read_stack_.push_chain(*NextElementPointer(read_head), *last);
    }
    NextElementPointer(read_head) = nullptr;
    return read_head;
  }

 private:
  LinkStack<T> read_stack_;
  LinkStack<T> write_stack_;
};

}  //  namespace atomic
}  //  namespace rx
