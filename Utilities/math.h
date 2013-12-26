//
//  math.h
//  rivenx
//
//  Created by Jean-Francois Roy on 26/12/13.
//  Copyright (c) 2013 MacStorm. All rights reserved.
//

#pragma once

#if !defined(__cplusplus)
#error "This file requires C++"
#endif

namespace rx {

template <typename T>
static inline
T clamp(T minimum, T maximum, T value)
{
  return value < minimum ? minimum : (value > maximum ? maximum : value);
}

} // namespace rx
