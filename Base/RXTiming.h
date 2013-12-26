/*
 *  RXTiming.h
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 21/03/2008.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#if !defined(RXTIMING_H)
#define RXTIMING_H

#include <stdint.h>
#include <mach/mach_time.h>
#include <sys/cdefs.h>

__BEGIN_DECLS

extern double g_RXTimebase;
extern double g_RX1_Timebase;

RX_INLINE uint64_t RXTimingNow() { return mach_absolute_time(); }
RX_INLINE double RXTimingTimestampDelta(uint64_t end, uint64_t start)
{
  if (end >= start)
    return g_RXTimebase * (double)(end - start);
  else
    return g_RXTimebase * -1 * (double)(start - end);
}
RX_INLINE uint64_t RXTimingOffsetTimestamp(uint64_t timestamp, double offset) { return (uint64_t)(g_RX1_Timebase * offset) + timestamp; }

extern void RXTimingUpdateTimebase(void);

__END_DECLS

#endif // RXTIMING_H
