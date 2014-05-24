//
//  osspinlock.h
//

#pragma once

#import "Base/cxx_policies.h"

namespace rx {

class OSSpinlockGuard : public noncopyable
{
public:
	explicit OSSpinlockGuard(OSSpinLock* lock) : lock_(lock) { OSSpinLockLock(lock_); }
	~OSSpinlockGuard() { OSSpinLockUnlock(lock_); }
private:
	OSSpinLock* lock_;
};

class OSSpinlock : public noncopyable
{
public:
  typedef OSSpinLock* native_handle_type;

  constexpr OSSpinlock() noexcept : lock_(OS_SPINLOCK_INIT) {}
  ~OSSpinlock() noexcept {}

  void lock() noexcept { OSSpinLockLock(&lock_); }
  bool try_lock() noexcept { return OSSpinLockTry(&lock_); }
  void unlock() noexcept { OSSpinLockUnlock(&lock_); }

  native_handle_type native_handle() { return &lock_; }

private:
  OSSpinLock lock_;
};

} // namespace rx
