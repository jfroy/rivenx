// Copyright 2015 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#include <iostream>
#include <iterator>
#include <random>

#include "Base/atomic/spc_queue.h"

using namespace std;

namespace {

random_device rd;
default_random_engine re(rd());
using queue = rx::atomic::SPCQueue<decltype(re)::result_type>;

void assert_empty(const queue::iterator& first, const queue::iterator& last) {
  release_assert(std::distance(first, last) == 0);
}

void assert_one_elem(const queue::iterator& first, const queue::iterator& last, const queue::value_type& v) {
  release_assert(std::distance(first, last) == 1);
  bool equal = *first == v;
  release_assert(equal);
}

void test_enqueue_noresize() {
  queue q;
  auto val = re();
  release_assert(q.TryEnqueue(val) == false);
}

void test_peek_noresize() {
  queue q;
  auto range = q.DequeueRange();
  assert_empty(std::begin(range), std::end(range));
}

void test_consume_noresize() {
  queue q;
  auto range = q.DequeueRange();
  assert_empty(std::begin(range), std::end(range));
  q.Consume(range);
}

void test_enqueue_peek() {
  queue q;
  q.Resize(1);
  auto val = re();
  release_assert(q.TryEnqueue(val));
  auto range = q.DequeueRange();
  assert_one_elem(std::begin(range), std::end(range), val);
}

void test_enqueue_peek_enqueue() {
  queue q;
  q.Resize(1);
  auto val = re();
  release_assert(q.TryEnqueue(val));
  auto range = q.DequeueRange();
  assert_one_elem(std::begin(range), std::end(range), val);
  release_assert(q.TryEnqueue(val) == false);
}

void test_enqueue_peek_consume_peak() {
  queue q;
  q.Resize(1);
  auto val = re();
  release_assert(q.TryEnqueue(val));
  auto range = q.DequeueRange();
  assert_one_elem(std::begin(range), std::end(range), val);
  q.Consume(range);
  range = q.DequeueRange();
  assert_empty(std::begin(range), std::end(range));
}

void test_enqueue_peek_consume_enqueue() {
  queue q;
  q.Resize(1);
  auto val = re();
  release_assert(q.TryEnqueue(val));
  auto range = q.DequeueRange();
  assert_one_elem(std::begin(range), std::end(range), val);
  q.Consume(range);
  release_assert(q.TryEnqueue(val));
}

void test_enqueue_one_too_many() {
  queue q;
  q.Resize(1);
  auto val = re();
  release_assert(q.TryEnqueue(val));
  release_assert(q.TryEnqueue(val) == false);
}

void test_peek_twice() {
  queue q;
  q.Resize(1);
  auto val = re();
  release_assert(q.TryEnqueue(val));
  auto range = q.DequeueRange();
  assert_one_elem(std::begin(range), std::end(range), val);
  range = q.DequeueRange();
  assert_one_elem(std::begin(range), std::end(range), val);
}

struct MoveOnlyValue : public rx::noncopyable {
  MoveOnlyValue() = default;
  MoveOnlyValue(MoveOnlyValue&& r) {}
};

void test_move_enqueue() {
  using queue = rx::atomic::SPCQueue<MoveOnlyValue>;
  queue q;
  q.Resize(5);
  MoveOnlyValue values[5];
  q.TryEnqueue(make_move_iterator(begin(values)), make_move_iterator(end(values)));
}

}  // namespace

extern void pc_queue_tests();
void pc_queue_tests() {
  test_enqueue_noresize();
  test_peek_noresize();
  test_consume_noresize();
  test_enqueue_peek();
  test_enqueue_peek_enqueue();
  test_enqueue_peek_consume_peak();
  test_enqueue_peek_consume_enqueue();
  test_enqueue_one_too_many();
  test_peek_twice();
  test_move_enqueue();
}
