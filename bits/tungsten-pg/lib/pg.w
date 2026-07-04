# Tungsten PG — PostgreSQL adapter for Tungsten
# Provides connection management, query execution, result handling,
# connection pooling, and type mapping.

in Tungsten:PG

use connection
use result
use pool
use type_map

VERSION = "0.1.0"

# Quick connection — returns a Connection for one-off usage
-> connect(url = nil, **options)
  config = if url
    ConnectionConfig.parse_url(url)
  else
    ConnectionConfig.new(**options)

  Connection.new(config).connect

# Connection pool — for application-level connection management
-> pool(url = nil, size: 5, timeout: 5, **options)
  config = if url
    ConnectionConfig.parse_url(url)
  else
    ConnectionConfig.new(**options)

  Pool.new(config, size: size, timeout: timeout)

# Execute a query using the default pool
-> exec(sql, *params)
  self.default_pool.with_connection -> (conn)
    conn.exec(sql, *params)

-> query(sql, *params)
  self.default_pool.with_connection -> (conn)
    conn.query(sql, *params)

# Default pool singleton
@@default_pool = nil

-> default_pool
  @@default_pool || <! "No default pool configured. Call PG.configure first."

-> configure(url = nil, **options)
  @@default_pool = pool(url, **options)


# Connection configuration
+ ConnectionConfig
  ro :host
  ro :port
  ro :database
  ro :username
  ro :password
  ro :sslmode
  ro :options

  -> new(host: "localhost", port: 5432, database:, username: nil, password: nil, sslmode: "prefer", **options)
    @host     = host
    @port     = port
    @database = database
    @username = username
    @password = password
    @sslmode  = sslmode
    @options  = options

  -> .parse_url(url)
    # postgres://user:pass@host:port/dbname?sslmode=require
    uri = URI.parse(url)
    self.new(
      host:     uri.host,
      port:     uri.port || 5432,
      database: uri.path.sub("/", ""),
      username: uri.user,
      password: uri.password,
      sslmode:  uri.query_params["sslmode"] || "prefer"
    )

  -> to_conninfo
    parts = ["host=#{@host}", "port=#{@port}", "dbname=#{@database}"]
    parts.push("user=#{@username}") if @username
    parts.push("password=#{@password}") if @password
    parts.push("sslmode=#{@sslmode}")
    parts.join(" ")
