# Carbide::Job — declarative job definition
# A Job declares *what* to do: queue, retry policy, scheduling.
# A Worker runs the job. Jobs are enqueued; workers dequeue and execute.

in Tungsten:Carbide

+ Job
  ro :id
  ro :arguments
  ro :enqueued_at
  ro :scheduled_at
  ro :attempts
  ro :max_attempts
  ro :last_error

  @@queue         = :default
  @@retry_count   = 3
  @@retry_backoff = :exponential
  @@retry_delay   = 5  # seconds
  @@priority      = :normal
  @@timeout       = 300  # seconds

  # --- Class-level DSL ---

  -> .queue_as(name)
    @@queue = name

  -> .retry_policy(count: 3, backoff: :exponential, delay: 5)
    @@retry_count   = count
    @@retry_backoff = backoff
    @@retry_delay   = delay

  -> .priority_level(level)
    @@priority = level

  -> .timeout_after(seconds)
    @@timeout = seconds

  # --- Enqueue ---

  -> .perform_async(*args)
    job = self.new(*args)
    JobQueue.enqueue(job)
    job

  -> .perform_in(delay, *args)
    job = self.new(*args)
    job.schedule_at(Time.now + delay)
    JobQueue.enqueue(job)
    job

  -> .perform_at(time, *args)
    job = self.new(*args)
    job.schedule_at(time)
    JobQueue.enqueue(job)
    job

  # --- Instance ---

  -> new(*args)
    @id           = Random.uuid
    @arguments    = args
    @enqueued_at  = Time.now
    @scheduled_at = nil
    @attempts     = 0
    @max_attempts = @@retry_count
    @last_error   = nil

  -> schedule_at(time)
    @scheduled_at = time

  -> ready?
    @scheduled_at.nil? || @scheduled_at <= Time.now

  # Override in subclasses — the actual work
  -> perform(*args)
    <! "Job#perform must be implemented"

  # Called by the worker
  -> execute
    @attempts += 1
    begin
      Timeout.run(@@timeout) ->
        self.perform(*@arguments)
      self.on_success
    rescue error
      @last_error = error
      if self.retryable?
        self.retry_later
      else
        self.on_failure(error)
        <! error

  -> retryable?
    @attempts < @max_attempts

  -> retry_later
    delay = case @@retry_backoff
      :exponential => @@retry_delay * (2 ** (@attempts - 1))
      :linear      => @@retry_delay * @attempts
      :fixed       => @@retry_delay
      => @@retry_delay

    self.class.perform_in(delay, *@arguments)
    Logger.info("Job #{self.class.name}#{@id} retry #{@attempts}/#{@max_attempts} in #{delay}s")

  # Override for custom hooks
  -> on_success
    nil

  -> on_failure(error)
    Logger.error("Job #{self.class.name}#{@id} failed after #{@attempts} attempts: #{error.message}")

  -> to_h
    {
      id: @id,
      class: self.class.name,
      queue: @@queue,
      arguments: @arguments,
      attempts: @attempts,
      enqueued_at: @enqueued_at,
      scheduled_at: @scheduled_at
    }
