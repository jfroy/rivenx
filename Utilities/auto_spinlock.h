//
//  auto_spinlock.h
//  rivenx
//
//  Created by Jean-Francois Roy on 09/10/2010.
//

#ifndef AUTO_SPINLOCK_H
#define AUTO_SPINLOCK_H

#include <libkern/OSAtomic.h>

class auto_spinlock {
public:
  auto_spinlock(volatile OSSpinLock* lock) : m_lock(lock) { OSSpinLockLock(m_lock); }

  ~auto_spinlock() { OSSpinLockUnlock(m_lock); }

private:
  volatile OSSpinLock* m_lock;

  auto_spinlock(const auto_spinlock& rval) {}
  auto_spinlock& operator=(const auto_spinlock& rval) { return *this; }
};

#endif // AUTO_SPINLOCK_H
