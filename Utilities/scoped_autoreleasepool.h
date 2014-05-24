//
//  scoped_autoreleasepool.h
//

#pragma once

#import "Base/cxx_policies.h"

namespace rx {

class ScopedAutoreleasePool : public noncopyable
{
public:
	explicit ScopedAutoreleasePool() : pool_([NSAutoreleasePool new]) {}
	~ScopedAutoreleasePool() { [pool_ drain]; }
private:
	NSAutoreleasePool* pool_;
};

} // namespace rx
