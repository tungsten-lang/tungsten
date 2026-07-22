# PG::Objects::Index — represents a PostgreSQL index
# Provides index metadata and DDL generation.

in Tungsten:PG:Objects

+ Index
  ro :name
  ro :table
  ro :columns
  ro :unique
  ro :method
  ro :definition

  -> new(name:, table: nil, columns: [], unique: false, method: :btree, definition: nil)
    @name       = name
    @table      = table
    @columns    = columns
    @unique     = unique
    @method     = method
    @definition = definition

  -> unique? = @unique

  -> to_create_sql
    if @definition
      @definition
    else
      unique_str = "UNIQUE " if @unique
      method_str = " USING #{@method}" unless @method == :btree
      "CREATE #{unique_str}INDEX #{@name} ON #{@table}#{method_str} (#{@columns.join(', ')})"

  -> to_drop_sql
    "DROP INDEX IF EXISTS #{@name}"

  -> inspect
    unique_str = "UNIQUE " if @unique
    "#<Index #{unique_str}#{@name} ON #{@table} (#{@columns.join(', ')})>"
