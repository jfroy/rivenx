// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#pragma once

#if defined(__cplusplus)

#include <type_traits>

namespace rx {

template <typename T, typename U>
inline
typename std::enable_if<std::is_integral<T>::value, T>::type
BUFFER_OFFSET(T buffer, U bytes) {
	return static_cast<T>(buffer + bytes);
}

template <typename T, typename U>
inline
typename std::enable_if<std::is_pointer<T>::value, T>::type
BUFFER_OFFSET(T buffer, U bytes) {
	return reinterpret_cast<T>(BUFFER_OFFSET(reinterpret_cast<uintptr_t>(buffer), bytes));
}

template <typename T>
inline size_t
BUFFER_DELTA(typename std::enable_if<std::is_integral<T>::value, T>::type head_ptr, T read_ptr) {
	return read_ptr - head_ptr;
}

template <typename T>
inline size_t
BUFFER_DELTA(typename std::enable_if<std::is_pointer<T>::value, T>::type head_ptr, T read_ptr) {
	return BUFFER_DELTA(reinterpret_cast<uintptr_t>(head_ptr), reinterpret_cast<uintptr_t>(read_ptr));
}

template <typename T>
inline
typename std::enable_if<std::is_unsigned<T>::value, T>::type
BUFFER_ALIGN(T buffer, size_t a) {
	T mask = static_cast<T>(a - 1);
	return (buffer + mask) & (~mask);
}

template <typename T>
inline
typename std::enable_if<std::is_pointer<T>::value, T>::type
BUFFER_ALIGN(T buffer, size_t a) {
	return reinterpret_cast<T>(BUFFER_ALIGN(reinterpret_cast<uintptr_t>(buffer), a));
}

template <typename T>
inline void BUFFER_ADD_BYTES(T& buffer, size_t bytes) {
	buffer = BUFFER_OFFSET(buffer, bytes);
}

template <typename T>
inline size_t BUFFER_ALIGN_SIZE(T buffer, size_t a) {
	return BUFFER_DELTA(buffer, BUFFER_ALIGN(buffer, a));
}

} // namespace rx {

#else // defined(__cplusplus)

#define BUFFER_OFFSET(buffer, bytes) (__typeof__(buffer))((uintptr_t)(buffer) + (bytes))
#define BUFFER_ADD_BYTES(buffer, bytes) (buffer) = (__typeof__(buffer))(((uintptr_t)(buffer)) + (bytes))

#define BUFFER_DELTA(head_ptr, read_ptr) ((size_t)(((uintptr_t)(read_ptr)) - ((uintptr_t)(head_ptr))))

#define BUFFER_ALIGN(buffer, a) (__typeof__(buffer))(((uintptr_t)(buffer) + ((a)-1ul)) & ~((a)-1ul))
#define BUFFER_ALIGN_SIZE(buffer, a) (size_t)((uintptr_t)BUFFER_ALIGN((buffer), (a)) - (uintptr_t)(buffer))

#endif
