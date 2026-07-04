# Carbide::Worker — background job processing
# Enqueue jobs for async execution with retry logic and scheduling.

in Tungsten:Carbide

+ Worker
  ro :job_id
  ro :queue
  ro :arguments
  ro :enqueued_at
  ro :attempts

  @@default_queue     = :default
  @@max_retries       = 3
  @@retry_delay       = 30  # seconds
  @@retry_backoff     = :exponential

  # --- Class-level configuration ---

  -> .queue_as(name)
    @@default_queue = name

  -> .retry_limit(n)
    @@max_retries = n

  -> .retry_delay(seconds)
    @@retry_delay = seconds

  # --- Enqueue interface ---

  -> .perform_async(*args)
    job = self.new(args)
    Carbide:JobQueue.enqueue(job)
    job.job_id

  -> .perform_in(delay, *args)
    job = self.new(args)
    job.scheduled_at = Time.now + delay
    Carbide:JobQueue.enqueue(job)
    job.job_id

  -> .perform_at(time, *args)
    job = self.new(args)
    job.scheduled_at = time
    Carbide:JobQueue.enqueue(job)
    job.job_id

  # --- Instance ---

  -> new(@arguments)
    @job_id      = Random.uuid
    @queue       = @@default_queue
    @enqueued_at = Time.now
    @attempts    = 0
    @scheduled_at = nil

  # Override in subclasses — the actual job logic
  -> perform(*args)
    <! "Worker#perform must be implemented"

  # Called by the job runner
  -> execute
    @attempts += 1
    begin
      perform(*@arguments)
    rescue error
      if @attempts < @@max_retries
        delay = retry_delay_for(@attempts)
        self.class.perform_in(delay, *@arguments)
      else
        on_failure(error)
        <! error

  -> retry_delay_for(attempt)
    case @@retry_backoff
      :exponential => @@retry_delay * (2 ** (attempt - 1))
      :linear      => @@retry_delay * attempt
      =>             @@retry_delay

  # Override for custom failure handling
  -> on_failure(error)
    Logger.error("Worker #{self.class.name} failed after #{@attempts} attempts: #{error.message}")


# Simple in-memory job queue (production would use PG or Redis)
+ JobQueue
  @@queues = {}

  -> .enqueue(job)
    queue_name = job.queue
    @@queues[queue_name] ||= []
    @@queues[queue_name].push(job)

  -> .dequeue(queue_name = :default)
    queue = @@queues[queue_name] || []
    now = Time.now
    # Find first job that's ready to run
    idx = queue.find_index -> (job)
      job.scheduled_at.nil? || job.scheduled_at <= now
    if idx
      queue.delete_at(idx)
    else
      nil

  -> .size(queue_name = :default)
    (@@queues[queue_name] || []).size

  -> .clear(queue_name = :default)
    @@queues[queue_name] = []

  -> .queues
    @@queues.keys
