//
//  RXBase.h
//  rivenx
//

#if !defined(RX_BASE_H)
#define RX_BASE_H

#import <sys/cdefs.h>
#import <stdbool.h>
#import <stdint.h>
#import <stdlib.h>

#import <TargetConditionals.h>
#import <Availability.h>

#import <libkern/OSAtomic.h>
#import <libkern/OSByteOrder.h>

#import <Block.h>
#import <dispatch/dispatch.h>

// assertions
#if !__has_extension(cxx_static_assert)
#define static_assert(e, m) enum {__STATIC_ASSERT_INTERNAL_VARNAME##__LINE__ = 1 / !!(e)}
#endif

__BEGIN_DECLS
void __assert_rtn(const char*, const char*, int, const char*) __dead2;
__END_DECLS

#if defined(DEBUG)
#define release_assert(e) (__builtin_expect(!(e), 0) ? __assert_rtn(__PRETTY_FUNCTION__, __FILE__, __LINE__, #e) : (void)0)
#define debug_assert(e) release_assert(e)
#else
#define release_assert(e) (__builtin_expect(!(e), 0) ? __assert_rtn(__PRETTY_FUNCTION__, "", 0, #e) : (void)0)
#define debug_assert(e) ((void)0)
#endif

// attributes
#define RX_UNUSED __attribute__((unused))
#define RX_INLINE static inline __attribute__((always_inline))

#define RX_DEPRECATED __attribute__((deprecated))
#define RX_DEPRECATED_M(s) __attribute__((deprecated(s)))

#define RX_UNAVAILABLE __attribute__((unavailable))
#define RX_UNAVAILABLE_M(s) __attribute__((unavailable(s)))

// GCD macros
#define QUEUE_HIGH dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)
#define QUEUE_DEFAULT dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
#define QUEUE_LOW dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)
#define QUEUE_MAIN dispatch_get_main_queue()

// other
#define ARRAY_LENGTH(array) (sizeof(array) / sizeof((array)[0]))

__BEGIN_DECLS

//! Formats and logs the specified message to stdout and to CrashReporter before calling abort().
extern void rx_abort(const char* format, ...) __attribute__((noreturn)) __attribute__((format(printf, 1, 2)));

__END_DECLS

// Objective-C specific section
#if defined(__OBJC__)

#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSValue.h>

#endif // defined(__OBJC__)

#endif // RX_BASE_H
