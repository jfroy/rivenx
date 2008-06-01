/*
 *  RXTiming.c
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 21/03/2008.
 *  Copyright 2008 MacStorm. All rights reserved.
 *
 */

#include "RXTiming.h"

double g_RXTimebase = 0.0;

extern void RXTimingUpdateTimebase() {
	mach_timebase_info_data_t info;
	kern_return_t err = mach_timebase_info( &info );

	// convert the timebase into seconds
	if (err == KERN_SUCCESS) g_RXTimebase = 1e-9 * (double) info.numer / (double) info.denom;
}
