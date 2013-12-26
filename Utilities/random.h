//
//  random.h
//  rivenx
//
//  Created by Jean-Francois Roy on 26/12/13.
//  Copyright (c) 2013 MacStorm. All rights reserved.
//

#pragma once

#include <sys/cdefs.h>

__BEGIN_DECLS

// uniform distribution
extern uint32_t rx_rnd_range(uint32_t lower, uint32_t upper);
extern double rx_rnd_rangef(double lower, double upper);

// clamped normal distribution
extern uint32_t rx_rnd_range_normal_clamped(uint32_t mean, uint32_t spread);

// random boolean (unifom)
extern bool rx_rnd_bool();

__END_DECLS
