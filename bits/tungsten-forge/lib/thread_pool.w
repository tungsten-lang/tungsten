# Forge::ThreadPool — work-stealing thread pool
# Each worker has a local deque; idle workers steal from busy workers

in Tungsten:Forge

+ ThreadPool
  ro :workers
  ro :max_queue
  ro :threads

  -> new(workers:, max_queue: 10_000)
    @workers   = workers
    @max_queue = max_queue
    @threads   = []
    @queues    = []  # per-worker deques
    @running   = false
    @next      = Atomic.new(0)  # round-robin counter

  -> start
    @running = true

    @workers.times -> (i)
      queue = WorkStealingDeque.new(@max_queue / @workers)
      @queues.push(queue)

      thread = Thread.new ->
        self.worker_loop(i, queue)
      @threads.push(thread)

  -> submit(task)
    # Round-robin assignment to worker queues
    idx = @next.increment % @workers
    unless @queues[idx].push(task)
      # Queue full — try to find another worker with space
      @queues.each_with_index -> (q, i)
        next if i == idx
        return nil if q.push(task)
      Logger.warn("ThreadPool: all queues full, dropping task")

  -> shutdown(wait: true)
    @running = false
    if wait
      @threads.each -> (t) t.join(timeout: 30)
    else
      @threads.each -> (t) t.kill

  -> stats
    {
      workers: @workers,
      active: @threads.count(-> (t) t.alive?),
      queued: @queues.sum(-> (q) q.size)
    }

  # --- Worker loop with work-stealing ---

  -> worker_loop(id, queue)
    while @running
      # Try own queue first
      task = queue.pop

      # If empty, steal from another worker
      unless task
        task = self.steal_from_others(id)

      if task
        begin
          task.call
        rescue error
          Logger.error("ThreadPool worker [id]: [error.message]")
      else
        # No work available — brief sleep before retrying
        Thread.sleep(0.001)

  -> steal_from_others(my_id)
    # Try each other worker's queue (randomized to avoid contention)
    indices = (0...@workers).to_a.shuffle
    indices.each -> (i)
      next if i == my_id
      stolen = @queues[i].steal
      return stolen if stolen
    nil


  # --- Lock-free work-stealing deque ---

  + WorkStealingDeque
    ro :capacity

    -> new(@capacity)
      @buffer = Array.new(@capacity)
      @top    = Atomic.new(0)  # steal from top
      @bottom = Atomic.new(0)  # push/pop from bottom

    -> push(item)
      bottom = @bottom.get
      top = @top.get
      size = bottom - top
      return false if size >= @capacity

      @buffer[bottom % @capacity] = item
      @bottom.set(bottom + 1)
      true

    -> pop
      bottom = @bottom.get - 1
      @bottom.set(bottom)
      top = @top.get

      if top <= bottom
        item = @buffer[bottom % @capacity]
        if top == bottom
          # Last item — compete with stealers
          unless @top.compare_and_swap(top, top + 1)
            item = nil
          @bottom.set(top + 1)
        item
      else
        @bottom.set(top)
        nil

    -> steal
      top = @top.get
      bottom = @bottom.get
      return nil if top >= bottom

      item = @buffer[top % @capacity]
      if @top.compare_and_swap(top, top + 1)
        item
      else
        nil  # lost race to another stealer

    -> size
      bottom = @bottom.get
      top = @top.get
      [bottom - top, 0].max

    -> empty?
      self.size == 0
