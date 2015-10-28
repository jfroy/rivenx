// Copyright 2015 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#include "Base/atomic/link_stack.h"

using namespace std;

namespace {

struct Node {
  int value{0};
  Node* next{nullptr};
};

using Stack = rx::atomic::LinkStack<Node>;

void test_push_pop() {
  Stack stack;
  Node n;
  stack.push(n);
  auto np = stack.try_pop();
  release_assert(&n == np);
}

}  // namespace

extern void link_stack_tests();
void link_stack_tests() { test_push_pop(); }
