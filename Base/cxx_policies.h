//
//  cxx_policies.h
//

#pragma once

#import "RXBase.h"


namespace rx {

//! Inherit this type to disallow copying the derived type.
struct noncopyable
{
  noncopyable() = default;
	noncopyable(noncopyable const& rhs) = delete;
	noncopyable& operator=(noncopyable const& rhs) = delete;
};

} // namespace rx {
