// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#include "Base/cxx_policies.h"
#include "Base/integer.h"
#include "Base/next_element_helper.h"

namespace rx {
namespace atomic {

template <typename T>
class LinkStack : public noncopyable {
 public:
  using value_type = T;
  using reference = value_type&;
  using pointer = value_type*;

  LinkStack() {
    s_.stack.head = nullptr;
    s_.stack.generation = 0;
  }

  void push(reference element) noexcept {
    Storage expected;
    Storage desired;
    expected.opaque = s_.opaque;
    desired.stack.head = &element;
    do {
      NextElementPointer(element) = expected.stack.head;
      desired.stack.generation = expected.stack.generation + 1;
      expected.opaque = __sync_val_compare_and_swap(&s_.opaque, expected.opaque, desired.opaque);
    } while (expected.opaque != desired.opaque);
  }

  void push_chain(reference head, reference tail) noexcept {
    Storage expected;
    Storage desired;
    expected.opaque = s_.opaque;
    desired.stack.head = &first;
    do {
      NextElementPointer(last) = expected.stack.head;
      desired.stack.generation = expected.stack.generation + 1;
      expected.opaque = __sync_val_compare_and_swap(&s_.opaque, expected.opaque, desired.opaque);
    } while (expected.opaque != desired.opaque);
  }

  pointer try_pop() noexcept {
    Storage expected;
    Storage desired;
    expected.opaque = s_.opaque;
    if (!expected.stack.head) {
      return nullptr;
    }
    do {
      desired.stack.head = NextElementPointer(expected.stack.head);
      desired.stack.generation = expected.stack.generation + 1;
      expected.opaque = __sync_val_compare_and_swap(&s_.opaque, expected.opaque, desired.opaque);
    } while (expected.opaque != desired.opaque);
    NextElementPointer(expected.stack.head) = nullptr;
    return expected.stack.head;
  }

  pointer try_pop_all() noexcept {
    Storage expected;
    Storage desired;
    expected.opaque = s_.opaque;
    if (!expected.stack.head) {
      return nullptr;
    }
    desired.stack.head = nullptr;
    do {
      desired.stack.generation = expected.stack.generation + 1;
      expected.opaque = __sync_val_compare_and_swap(&s_.opaque, expected.opaque, desired.opaque);
    } while (expected.opaque != desired.opaque);
    return expected.stack.head;
  }

 private:
  struct Stack {
    pointer head;
    typename Integer<sizeof(pointer)>::type generation;
  };
  struct Storage {
    union alignas(sizeof(Stack)) {
      Stack stack;
      typename Integer<sizeof(Stack)>::type opaque;
    };
  };

  Storage s_;
};

}  //  namespace atomic
}  //  namespace rx
