-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

mutex = Mutex.new()
counter = Atomic.new(0)
workers = []
worker_count = 4
i = 0
while i < worker_count
  worker = Thread.new ->
    j = 0
    while j < 250
      mutex.synchronize ->
        counter.store(counter.load() + 1)
      j += 1
  workers.push(worker)
  i += 1

i = 0
while i < worker_count
  workers[i].join()
  i += 1
check("mutex.thread.exclusion", counter.load() == 1000)

mutex.lock()
non_owner_result = Channel.new(1)
non_owner = Thread.new ->
  begin
    mutex.unlock()
    non_owner_result.send("no error")
  rescue error
    non_owner_result.send(error.to_s)
non_owner.join()
non_owner_error = non_owner_result.receive()
check("mutex.thread.non_owner", non_owner_error.include?("non-owner"))
mutex.unlock()

cancel_mutex = Mutex.new()
ready = Channel.new(1)
cancelled = Thread.new ->
  cancel_mutex.lock()
  ready.send(true)
  while true
    sleep(1)
ready.receive()
cancelled.kill()
cancelled.join()
check("mutex.thread.cancel.release", cancel_mutex.try_lock())
cancel_mutex.unlock()

<< "mutex_thread_spec: all checks passed"
