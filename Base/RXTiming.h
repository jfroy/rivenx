/*
 *  RXTiming.h
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 21/03/2008.
 *  Copyright 2008 MacStorm. All rights reserved.
 *
 */

#if !defined(RXTIMING_H)
#define RXTIMING_H

#include <stdint.h>
#include <mach/mach_time.h>
#include <sys/cdefs.h>

__BEGIN_DECLS

extern double g_RXTimebase;

CF_INLINE uint64_t RXTimingNow() {return mach_absolute_time();}
CF_INLINE double RXTimingTimestampDelta(uint64_t endTime, uint64_t startTime) {return g_RXTimebase * (double)(endTime - startTime);}

extern void RXTimingUpdateTimebase();

__END_DECLS

#endif // RXTIMING_H
