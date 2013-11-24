//
//  RXBufferMacros.h
//  rivenx
//

#if !defined(RX_BUFFER_MACROS_H)
#define RX_BUFFER_MACROS_H

#define BUFFER_OFFSET(buffer, bytes) (__typeof__(buffer))((uintptr_t)(buffer) + (bytes))
#define BUFFER_NOFFSET(buffer, bytes) (__typeof__(buffer))((uintptr_t)(buffer) - (bytes))
#define BUFFER_ADD_OFFSET(buffer, bytes) (buffer) = BUFFER_OFFSET((buffer), (bytes))

#define BUFFER_DELTA(head_ptr, read_ptr) ((size_t)(((uintptr_t)(read_ptr)) - ((uintptr_t)(head_ptr))))

#define BUFFER_ALIGN(buffer, a) (__typeof__(buffer))(((uintptr_t)(buffer) + (a - 1ul)) & ~(a - 1ul))
#define BUFFER_ALIGN_SIZE(buffer, a) (size_t)((uintptr_t)BUFFER_ALIGN((buffer), (a)) - (uintptr_t)(buffer))

#define BUFFER_ALIGN2(buffer) BUFFER_ALIGN(buffer, 2ul)
#define BUFFER_ALIGN4(buffer) BUFFER_ALIGN(buffer, 4ul)
#define BUFFER_ALIGN8(buffer) BUFFER_ALIGN(buffer, 8ul)
#define BUFFER_ALIGN16(buffer) BUFFER_ALIGN(buffer, 16ul)

#endif // RX_BUFFER_MACROS_H
