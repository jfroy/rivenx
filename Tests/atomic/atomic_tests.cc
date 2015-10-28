// Copyright 2015 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

extern void pc_queue_tests();
extern void link_stack_tests();

int main(int argc, const char* argv[]) {
  pc_queue_tests();
  link_stack_tests();
}
