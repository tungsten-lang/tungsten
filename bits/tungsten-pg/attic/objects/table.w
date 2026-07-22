# PG::Objects::Table — represents a PostgreSQL table
# Provides introspection, column listing, and DDL generation.

in Tungsten:PG:Objects

+ Table
  ro :name
  ro :schema
  ro :columns
  ro :indexes
  ro :constraints

  -> new(@name, schema: "public")
    @schema      = schema
    @columns     = []
    @indexes     = []
    @constraints = []

  # Load table metadata from a live connection
  -> .from_connection(conn, name, schema: "public")
    table = self.new(name, schema: schema)
    table.load_columns(conn)
    table.load_indexes(conn)
    table

  -> load_columns(conn)
    @columns = conn.query(
      "SELECT column_name, data_type, is_nullable, column_default, ordinal_position
       FROM information_schema.columns
       WHERE table_schema = $1 AND table_name = $2
       ORDER BY ordinal_position",
      @schema, @name
    ).map -> (row)
      Column.new(
        name:     row[:column_name],
        type:     row[:data_type],
        nullable: row[:is_nullable] == "YES",
        default:  row[:column_default],
        position: row[:ordinal_position]
      )

  -> load_indexes(conn)
    @indexes = conn.query(
      "SELECT indexname, indexdef FROM pg_indexes
       WHERE schemaname = $1 AND tablename = $2",
      @schema, @name
    ).map -> (row)
      Index.new(name: row[:indexname], definition: row[:indexdef])

  -> column(name)
    @columns.find(c -> c.name == name.to_s)

  -> has_column?(name)
    @columns.any?(c -> c.name == name.to_s)

  -> primary_key
    @columns.find(c -> c.primary_key?)

  -> qualified_name
    "#{@schema}.#{@name}"

  -> row_count(conn)
    conn.query_value("SELECT COUNT(*) FROM #{qualified_name}")

  # --- DDL generation ---

  -> to_create_sql
    col_defs = @columns.map(c -> c.to_sql).join(",\n  ")
    "CREATE TABLE #{qualified_name} (\n  #{col_defs}\n)"

  -> to_drop_sql
    "DROP TABLE IF EXISTS #{qualified_name}"

  -> exists?(conn)
    conn.table_exists?(@name)
