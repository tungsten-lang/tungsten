# PG::Objects::Database — represents a PostgreSQL database
# Provides database-level introspection and management.

in Tungsten:PG:Objects

+ Database
  ro :name
  ro :owner
  ro :encoding

  -> new(@name, owner: nil, encoding: "UTF8")
    @owner    = owner
    @encoding = encoding

  -> .current(conn)
    name = conn.query_value("SELECT current_database()")
    self.new(name)

  # List all tables in the public schema
  -> tables(conn)
    conn.query(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename"
    ).map -> (row)
      Table.from_connection(conn, row[:tablename])

  -> table_names(conn)
    conn.query(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename"
    ).pluck(:tablename)

  # List all schemas
  -> schemas(conn)
    conn.query(
      "SELECT schema_name FROM information_schema.schemata ORDER BY schema_name"
    ).pluck(:schema_name)

  # Database size in human-readable format
  -> size(conn)
    conn.query_value("SELECT pg_size_pretty(pg_database_size($1))", @name)

  # Active connections
  -> active_connections(conn)
    conn.query_value(
      "SELECT count(*) FROM pg_stat_activity WHERE datname = $1", @name
    )

  # --- DDL ---

  -> to_create_sql
    parts = ["CREATE DATABASE #{@name}"]
    parts.push("OWNER #{@owner}") if @owner
    parts.push("ENCODING '#{@encoding}'")
    parts.join(" ")

  -> to_drop_sql
    "DROP DATABASE IF EXISTS #{@name}"
