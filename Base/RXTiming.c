/*
 *  RXTiming.c
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 21/03/2008.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#include "RXTiming.h"

double g_RXTimebase = 0.0;
double g_RX1_Timebase = 0.0;

void RXTimingUpdateTimebase(void)
{
  mach_timebase_info_data_t info;
  kern_return_t err = mach_timebase_info(&info);
  debug_assert(err == KERN_SUCCESS);
  (void)err;

  // compute the timebase to seconds scale factor
  g_RXTimebase = 1e-9 * (double)info.numer / (double)info.denom;

  // compute its inverse to convert from seconds to timebase
  g_RX1_Timebase = 1.0 / g_RXTimebase;
}
