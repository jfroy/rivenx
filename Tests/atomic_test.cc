// Copyright 2015 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#include <iostream>
#include <iterator>
#include <random>

#include "Base/atomic/pc_queue.h"

using namespace std;

namespace {

random_device rd;
default_random_engine re(rd());
using queue = rx::atomic::FixedSinglePCQueue<decltype(re)::result_type>;

void assert_empty_rp(const queue::range_pair& rp) {
  release_assert(rp.first.first == rp.first.second && rp.second.first == rp.second.second);
}

void assert_one_elem_rp(const queue::range_pair& rp, const queue::value_type& v) {
  release_assert(rp.first.first + 1 == rp.first.second);
  release_assert(*rp.first.first == v);
  release_assert(rp.second.first == rp.second.second);
}

void test_enqueue_noresize() {
  queue q;
  auto val = re();
  release_assert(q.TryEnqueue(val) == false);
}

void test_peek_noresize() {
  queue q;
  auto rp = q.DequeuePeek();
  assert_empty_rp(rp);
}

void test_consume_noresize() {
  queue q;
  q.DequeueConsume();
}

void test_enqueue_peek() {
  queue q;
  q.Resize(1);
  auto val = re();
  release_assert(q.TryEnqueue(val));
  auto rp = q.DequeuePeek();
  assert_one_elem_rp(rp, val);
}

void test_enqueue_peek_enqueue() {
  queue q;
  q.Resize(1);
  auto val = re();
  release_assert(q.TryEnqueue(val));
  auto rp = q.DequeuePeek();
  assert_one_elem_rp(rp, val);
  release_assert(q.TryEnqueue(val) == false);
}

void test_enqueue_peek_consume_peak() {
  queue q;
  q.Resize(1);
  auto val = re();
  release_assert(q.TryEnqueue(val));
  auto rp = q.DequeuePeek();
  assert_one_elem_rp(rp, val);
  q.DequeueConsume();
  rp = q.DequeuePeek();
  assert_empty_rp(rp);
}

void test_enqueue_peek_consume_enqueue() {
  queue q;
  q.Resize(1);
  auto val = re();
  release_assert(q.TryEnqueue(val));
  auto rp = q.DequeuePeek();
  assert_one_elem_rp(rp, val);
  q.DequeueConsume();
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
  auto rp = q.DequeuePeek();
  assert_one_elem_rp(rp, val);
  rp = q.DequeuePeek();
  assert_one_elem_rp(rp, val);
}

struct MoveOnlyValue : public rx::noncopyable {
  MoveOnlyValue() = default;
  MoveOnlyValue(MoveOnlyValue&& r) {}
};

void test_move_enqueue() {
  using queue = rx::atomic::FixedSinglePCQueue<MoveOnlyValue>;
  queue q;
  q.Resize(5);
  MoveOnlyValue values[5];
  q.TryEnqueue(make_move_iterator(begin(values)), make_move_iterator(end(values)));
}

void test_iterator() {
  queue q;
  q.Resize(1);
  auto val = re();
  release_assert(q.TryEnqueue(val));
  auto rp = q.DequeuePeek();
  assert_one_elem_rp(rp, val);
  auto iter = queue::iterator(rp);
  release_assert(*iter == val);
  ++iter;
}

}  // namespace

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
  test_move_enqueue();
  test_iterator();
  return 0;
}
