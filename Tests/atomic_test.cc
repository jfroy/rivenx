// Copyright 2015 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#include <iostream>
#include <random>

#include "Base/atomic/pc_queue.h"

using namespace std;

random_device rd;
default_random_engine re(rd());
using queue = rx::atomic::FixedSinglePCQueue<decltype(re)::result_type>;

static void assert_empty_rp(const queue::range_pair& rp) {
  release_assert(rp.first.first == rp.first.second && rp.second.first == rp.second.second);
}

static void assert_one_elem_rp(const queue::range_pair& rp, const queue::value_type& v) {
  release_assert(rp.first.first + 1 == rp.first.second);
  release_assert(*rp.first.first == v);
  release_assert(rp.second.first == rp.second.second);
}

static void test_enqueue_noresize() {
  queue q;
  auto val = re();
  release_assert(q.try_enqueue(val) == false);
}

static void test_peek_noresize() {
  queue q;
  auto rp = q.dequeue_peek();
  assert_empty_rp(rp);
}

static void test_consume_noresize() {
  queue q;
  q.dequeue_consume();
}

static void test_enqueue_peek() {
  queue q;
  q.resize(1);
  auto val = re();
  release_assert(q.try_enqueue(val));
  auto rp = q.dequeue_peek();
  assert_one_elem_rp(rp, val);
}

static void test_enqueue_peek_enqueue() {
  queue q;
  q.resize(1);
  auto val = re();
  release_assert(q.try_enqueue(val));
  auto rp = q.dequeue_peek();
  assert_one_elem_rp(rp, val);
  release_assert(q.try_enqueue(val) == false);
}

static void test_enqueue_peek_consume_peak() {
  queue q;
  q.resize(1);
  auto val = re();
  release_assert(q.try_enqueue(val));
  auto rp = q.dequeue_peek();
  assert_one_elem_rp(rp, val);
  q.dequeue_consume();
  rp = q.dequeue_peek();
  assert_empty_rp(rp);
}

static void test_enqueue_peek_consume_enqueue() {
  queue q;
  q.resize(1);
  auto val = re();
  release_assert(q.try_enqueue(val));
  auto rp = q.dequeue_peek();
  assert_one_elem_rp(rp, val);
  q.dequeue_consume();
  release_assert(q.try_enqueue(val));
}

static void test_enqueue_one_too_many() {
  queue q;
  q.resize(1);
  auto val = re();
  release_assert(q.try_enqueue(val));
  release_assert(q.try_enqueue(val) == false);
}

static void test_peek_twice() {
  queue q;
  q.resize(1);
  auto val = re();
  release_assert(q.try_enqueue(val));
  auto rp = q.dequeue_peek();
  assert_one_elem_rp(rp, val);
  rp = q.dequeue_peek();
  assert_one_elem_rp(rp, val);
}

int main(int argc, const char* argv[]) {
  test_enqueue_noresize();
  test_peek_noresize();
  test_consume_noresize();
  test_enqueue_peek();
  test_enqueue_peek_enqueue();
  test_enqueue_peek_consume_peak();
  test_enqueue_peek_consume_enqueue();
  test_enqueue_one_too_many();
  test_peek_twice();
  return 0;
}
