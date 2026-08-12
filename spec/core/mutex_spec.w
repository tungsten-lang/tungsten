-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> dynamic_roundtrip(value)
  value.lock()
  held = value.locked?()
  value.unlock()
  held && !value.locked?()

mutex = Mutex.new()
check("mutex.initially.unlocked", !mutex.locked?())
check("mutex.try_lock", mutex.try_lock())
check("mutex.locked", mutex.locked?())
check("mutex.try_lock.busy", !mutex.try_lock())

reentrant_failed = false
begin
  mutex.lock()
rescue error
  reentrant_failed = error.to_s.include?("not reentrant")
check("mutex.lock.non_reentrant", reentrant_failed)
check("mutex.unlock.returns_self", mutex.unlock() == mutex)
check("mutex.unlock.clears", !mutex.locked?())

unlocked_failed = false
begin
  mutex.unlock()
rescue error
  unlocked_failed = error.to_s.include?("unlock of unlocked Mutex")
check("mutex.unlock.unlocked", unlocked_failed)

result = mutex.synchronize ->
  check("mutex.synchronize.locked", mutex.locked?())
  42
check("mutex.synchronize.result", result == 42)
check("mutex.synchronize.releases", !mutex.locked?())

raised = false
begin
  mutex.synchronize ->
    raise "protected failure"
rescue error
  raised = error.to_s.include?("protected failure")
check("mutex.synchronize.propagates", raised)
check("mutex.synchronize.ensure", !mutex.locked?())
check("mutex.dynamic.dispatch", dynamic_roundtrip(mutex))

<< "mutex_spec: all checks passed"
