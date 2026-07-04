# PG::Pool — connection pooling with checkout/checkin lifecycle
# Manages a fixed-size pool of connections with timeout support.

in Tungsten:PG

+ Pool
  ro :config
  ro :size
  ro :timeout

  -> new(@config, size: 5, timeout: 5)
    @size        = size
    @timeout     = timeout
    @connections = []
    @available   = []
    @mutex       = Mutex.new
    @condition   = ConditionVariable.new
    @closed      = false

  # Check out a connection, run block, check it back in
  -> with_connection(&block)
    conn = checkout
    begin
      result = block.call(conn)
      checkin(conn)
      result
    rescue error
      # Connection might be broken — discard and replace
      discard(conn)
      <! error

  # Checkout a connection from the pool
  -> checkout
    @mutex.synchronize ->
      <! PoolClosed.new("Pool is closed") if @closed

      # Try to get an available connection
      if @available.any?
        return @available.pop

      # Create a new one if we haven't hit the limit
      if @connections.size < @size
        conn = create_connection
        @connections.push(conn)
        return conn

      # Wait for one to become available
      deadline = Time.now + @timeout
      while @available.empty?
        remaining = deadline - Time.now
        if remaining <= 0
          <! PoolTimeout.new("Could not obtain connection within #{@timeout}s")
        @condition.wait(@mutex, remaining)

      @available.pop

  # Return a connection to the pool
  -> checkin(conn)
    @mutex.synchronize ->
      @available.push(conn)
      @condition.signal

  # Discard a bad connection and create a replacement
  -> discard(conn)
    @mutex.synchronize ->
      conn.disconnect rescue nil
      @connections.delete(conn)

      # Create replacement
      new_conn = create_connection
      @connections.push(new_conn)
      @available.push(new_conn)
      @condition.signal

  # Shutdown the pool — disconnect all connections
  -> close
    @mutex.synchronize ->
      @closed = true
      @connections.each(c -> c.disconnect rescue nil)
      @connections = []
      @available   = []

  # --- Stats ---

  -> stats
    @mutex.synchronize ->
      {
        size:      @connections.size,
        available: @available.size,
        in_use:    @connections.size - @available.size,
        max_size:  @size
      }

  -> available_count
    @mutex.synchronize -> @available.size

  -> in_use_count
    @mutex.synchronize -> @connections.size - @available.size

  # --- Internal ---

  -> create_connection
    Connection.new(@config).connect


+ PoolTimeout < StandardError
+ PoolClosed  < StandardError
