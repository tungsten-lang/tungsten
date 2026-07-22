# PG::Connection — manages a single PostgreSQL connection
# Provides query execution, prepared statements, transactions,
# and COPY protocol support.

in Tungsten:PG

+ Connection
  ro :config
  ro :connected
  ro :transaction_depth
  rw :type_map

  -> new(@config)
    @handle           = nil
    @connected        = false
    @transaction_depth = 0
    @type_map         = TypeMap.default
    @prepared         = {}

  -> connect
    @handle    = Native.pg_connect(@config.to_conninfo)
    @connected = true
    self

  -> disconnect
    if @connected
      Native.pg_finish(@handle)
      @connected = false
      @handle = nil
    self

  -> close = disconnect

  -> connected? = @connected

  # --- Query execution ---

  # Execute SQL with optional parameters, returns Result
  -> exec(sql, *params)
    ensure_connected!

    raw = if params.empty?
      Native.pg_exec(@handle, sql)
    else
      encoded = params.map(p -> @type_map.encode(p))
      Native.pg_exec_params(@handle, sql, encoded)

    Result.new(raw, @type_map)

  # Query is an alias for exec
  -> query(sql, *params)
    exec(sql, *params)

  # Execute and return the first row
  -> query_one(sql, *params)
    exec(sql, *params).first

  # Execute and return a single value
  -> query_value(sql, *params)
    row = query_one(sql, *params)
    row&.values&.first

  # --- Prepared statements ---

  -> prepare(name, sql)
    ensure_connected!
    Native.pg_prepare(@handle, name, sql)
    @prepared[name] = sql
    self

  -> exec_prepared(name, *params)
    ensure_connected!
    encoded = params.map(p -> @type_map.encode(p))
    raw = Native.pg_exec_prepared(@handle, name, encoded)
    Result.new(raw, @type_map)

  -> deallocate(name)
    exec("DEALLOCATE #{name}")
    @prepared.delete(name)

  # --- Transactions ---

  -> transaction(&block)
    if @transaction_depth > 0
      savepoint(&block)
    else
      begin_transaction
      begin
        result = block.call(self)
        commit
        result
      rescue error
        rollback
        <! error

  -> begin_transaction
    @transaction_depth += 1
    exec("BEGIN")

  -> commit
    exec("COMMIT")
    @transaction_depth -= 1

  -> rollback
    exec("ROLLBACK")
    @transaction_depth -= 1

  -> savepoint(&block)
    name = "sp_#{@transaction_depth}"
    @transaction_depth += 1
    exec("SAVEPOINT #{name}")
    begin
      result = block.call(self)
      exec("RELEASE SAVEPOINT #{name}")
      @transaction_depth -= 1
      result
    rescue error
      exec("ROLLBACK TO SAVEPOINT #{name}")
      @transaction_depth -= 1
      <! error

  -> in_transaction?
    @transaction_depth > 0

  # --- COPY protocol ---

  -> copy_in(sql, &block)
    ensure_connected!
    Native.pg_copy_in_start(@handle, sql)
    writer = CopyWriter.new(@handle)
    begin
      block.call(writer)
      writer.finish
    rescue error
      writer.abort(error.message)
      <! error

  -> copy_out(sql, &block)
    ensure_connected!
    Native.pg_copy_out_start(@handle, sql)
    while row = Native.pg_copy_out_row(@handle)
      block.call(row)

  # --- LISTEN/NOTIFY ---

  -> listen(channel)
    exec("LISTEN #{channel}")

  -> unlisten(channel)
    exec("UNLISTEN #{channel}")

  -> notify(channel, payload = nil)
    if payload
      exec("NOTIFY #{channel}, '#{payload}'")
    else
      exec("NOTIFY #{channel}")

  -> wait_for_notify(timeout: nil)
    Native.pg_wait_for_notify(@handle, timeout)

  # --- Utility ---

  -> server_version
    query_value("SHOW server_version")

  -> current_database
    query_value("SELECT current_database()")

  -> tables
    query("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")
      self.map(row -> row[:tablename])

  -> table_exists?(name)
    query_value("SELECT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = $1)", name)

  -> ensure_connected!
    <! ConnectionError.new("Not connected") unless @connected


+ CopyWriter
  -> new(@handle)

  -> write(data)
    Native.pg_copy_in_write(@handle, data)

  -> finish
    Native.pg_copy_in_finish(@handle)

  -> abort(message)
    Native.pg_copy_in_abort(@handle, message)


+ ConnectionError < StandardError
