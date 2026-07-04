# %class_name%Adapter — database adapter for %name% connections
in Tungsten:Carbide:Adapters

+ %class_name%Adapter < Carbide:Adapter
  ro :config
  ro :pool

  @@default_config = {
    host:     "localhost",
    port:     5432,
    database: "%name%_development",
    pool:     5,
    timeout:  5000
  }

  -> new(config = {})
    @config = @@default_config.merge(config)
    @pool   = ConnectionPool.new(size: @config[:pool])

  -> connect
    @pool.checkout -> (conn)
      conn.open(@config)
    self

  -> disconnect
    @pool.drain
    self

  -> connected?
    @pool.any?(conn -> conn.active?)

  # Execute a raw query
  -> execute(sql, *binds)
    with_connection -> (conn)
      conn.execute(sql, binds)

  # Query and return result set
  -> query(sql, *binds)
    with_connection -> (conn)
      conn.query(sql, binds)

  # Transaction support
  -> transaction(&block)
    with_connection -> (conn)
      conn.begin_transaction
      begin
        result = block.call(conn)
        conn.commit
        result
      rescue error
        conn.rollback
        <! error

  -> with_connection(&block)
    conn = @pool.checkout
    begin
      block.call(conn)
    ensure
      @pool.checkin(conn)

  # Schema introspection
  -> tables
    query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")
      self.map(row -> row[:table_name])

  -> columns(table_name)
    query("SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name = $1", table_name)
