# Mutex — a non-reentrant mutual-exclusion lock.
#
# Only the owner may unlock. synchronize always releases the lock when its
# block returns or raises. Mutexes are deliberately non-poisoning: after a
# cancelled owner is released, callers must decide whether protected state is
# still valid.
+ Mutex
  -> .new
    ccall("w_mutex_new")

  -> lock
    ccall("w_mutex_lock", self)

  -> try_lock
    ccall("w_mutex_try_lock", self)

  -> unlock
    ccall("w_mutex_unlock", self)

  -> locked?
    ccall("w_mutex_locked", self)

  -> synchronize(&)
    lock()
    result = nil
    begin
      result = yield
    ensure
      unlock()
    result
