/*
 *	RXAtomic.h
 *	rivenx
 *
 *	Created by Jean-Francois Roy on 08/08/06.
 *	Copyright 2006 MacStorm. All rights reserved.
 *
 */

#if !defined(_RXAtomic_)
#define _RXAtomic_

#include <stdbool.h>

#include <sys/cdefs.h>

#include <CoreFoundation/CFBase.h>
#include <libkern/OSAtomic.h>

__BEGIN_DECLS

#if __LP64__
typedef int64_t atomic_int_t;
#else
typedef int32_t atomic_int_t;
#endif

CF_INLINE bool RX_compare_and_swap(atomic_int_t oldvalue, atomic_int_t newvalue, atomic_int_t* pvalue) {
#if __LP64__
		return OSAtomicCompareAndSwap64Barrier(oldvalue, newvalue, pvalue);
#else
		return OSAtomicCompareAndSwap32Barrier(oldvalue, newvalue, pvalue);
#endif
}

__END_DECLS

#endif // _RXAtomic_
