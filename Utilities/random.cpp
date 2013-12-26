//
//  random.cpp
//  rivenx
//
//  Created by Jean-Francois Roy on 26/12/13.
//  Copyright (c) 2013 MacStorm. All rights reserved.
//

#include "random.h"

#include <random>

#include "Utilities/math.h"

static std::random_device rd;
static std::default_random_engine rng(rd());

uint32_t rx_rnd_range(uint32_t lower, uint32_t upper)
{
  std::uniform_int_distribution<uint32_t> dis(lower, upper);
  return dis(rng);
}

double rx_rnd_rangef(double lower, double upper)
{
  std::uniform_real_distribution<double> dis(lower, upper);
  return dis(rng);
}

uint32_t rx_rnd_range_normal_clamped(uint32_t mean, uint32_t spread)
{
  uint32_t lower = mean - spread;
  uint32_t upper = mean + spread;
  std::normal_distribution<double> dis(double(mean), 0.7);
  return rx::clamp<uint32_t>(lower, upper, std::round(dis(rng)));
}

bool rx_rnd_bool()
{
  return static_cast<bool>(rd() & 0x1);
}
