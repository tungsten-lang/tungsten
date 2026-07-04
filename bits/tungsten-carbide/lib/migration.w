# Carbide::Migration — schema changes for database evolution
# Each migration defines an `up` and optional `down` for reversibility.

in Tungsten:Carbide

+ Migration
  ro :version
  ro :name
  ro :direction

  -> new(@version, @name)
    @direction = :up
    @operations = []

  # Override in subclasses
  -> up
  -> down

  # Run the migration in the given direction
  -> migrate(direction = :up)
    @direction = direction
    case direction
      :up   => up
      :down => down

  # --- Schema DSL ---

  -> create_table(name, &block)
    table = TableDefinition.new(name)
    table.instance_eval(&block)
    @operations.push({op: :create_table, table: table})

  -> drop_table(name)
    @operations.push({op: :drop_table, name: name})

  -> add_column(table, name, type, **options)
    @operations.push({op: :add_column, table: table, name: name, type: type, options: options})

  -> remove_column(table, name)
    @operations.push({op: :remove_column, table: table, name: name})

  -> rename_column(table, old_name, new_name)
    @operations.push({op: :rename_column, table: table, old_name: old_name, new_name: new_name})

  -> change_column(table, name, type, **options)
    @operations.push({op: :change_column, table: table, name: name, type: type, options: options})

  -> add_index(table, columns, unique: false, name: nil)
    @operations.push({op: :add_index, table: table, columns: columns, unique: unique, name: name})

  -> remove_index(table, name:)
    @operations.push({op: :remove_index, table: table, name: name})

  -> add_foreign_key(from_table, to_table, column: nil, on_delete: nil)
    @operations.push({op: :add_foreign_key, from: from_table, to: to_table, column: column, on_delete: on_delete})

  -> add_reference(table, name, foreign_key: true, type: :integer, null: true)
    add_column(table, "#{name}_id", type, null: null)
    add_index(table, ["#{name}_id"])
    add_foreign_key(table, name.to_s.pluralize) if foreign_key

  -> execute(sql)
    @operations.push({op: :raw_sql, sql: sql})

  -> reversible(&block)
    rev = ReversibleBlock.new
    rev.instance_eval(&block)
    case @direction
      :up   => rev.up_block.call if rev.up_block
      :down => rev.down_block.call if rev.down_block

  # Generate SQL for all recorded operations
  -> to_sql
    @operations.map(op -> operation_to_sql(op)).join(";\n")

  -> operation_to_sql(op)
    case op.op
      :create_table  => op.table.to_sql
      :drop_table    => "DROP TABLE #{op.name}"
      :add_column    => "ALTER TABLE #{op.table} ADD COLUMN #{op.name} #{sql_type(op.type, op.options)}"
      :remove_column => "ALTER TABLE #{op.table} DROP COLUMN #{op.name}"
      :add_index     =>
        unique = "UNIQUE " if op.unique
        idx_name = op.name || "idx_#{op.table}_#{op.columns.join('_')}"
        "CREATE #{unique}INDEX #{idx_name} ON #{op.table} (#{op.columns.join(', ')})"
      :raw_sql       => op.sql

  [pure]
  -> sql_type(type, options = {})
    base = case type
      :string    => "VARCHAR(#{options[:limit] || 255})"
      :text      => "TEXT"
      :integer   => "INTEGER"
      :bigint    => "BIGINT"
      :float     => "DOUBLE PRECISION"
      :decimal   => "NUMERIC(#{options[:precision] || 10}, #{options[:scale] || 0})"
      :boolean   => "BOOLEAN"
      :date      => "DATE"
      :datetime  => "TIMESTAMP"
      :timestamp => "TIMESTAMPTZ"
      :uuid      => "UUID"
      :jsonb     => "JSONB"
      :binary    => "BYTEA"
      =>          type.to_s.upcase

    base += " NOT NULL" if options[:null] == false
    base += " DEFAULT #{options[:default]}" if options[:default]
    base


# Table definition DSL used inside create_table blocks
+ TableDefinition
  ro :name
  ro :columns

  -> new(@name)
    @columns = []
    # Always add an id column unless told not to
    @columns.push({name: "id", type: :bigint, options: {primary_key: true, null: false}})

  -> column(name, type, **options)
    @columns.push({name: name, type: type, options: options})
    self

  # Convenience column type methods
  -> string(name, **opts)     = column(name, :string, **opts)
  -> text(name, **opts)       = column(name, :text, **opts)
  -> integer(name, **opts)    = column(name, :integer, **opts)
  -> bigint(name, **opts)     = column(name, :bigint, **opts)
  -> float(name, **opts)      = column(name, :float, **opts)
  -> decimal(name, **opts)    = column(name, :decimal, **opts)
  -> boolean(name, **opts)    = column(name, :boolean, **opts)
  -> date(name, **opts)       = column(name, :date, **opts)
  -> datetime(name, **opts)   = column(name, :datetime, **opts)
  -> timestamp(name, **opts)  = column(name, :timestamp, **opts)
  -> uuid(name, **opts)       = column(name, :uuid, **opts)
  -> jsonb(name, **opts)      = column(name, :jsonb, **opts)
  -> binary(name, **opts)     = column(name, :binary, **opts)

  -> timestamps
    column("created_at", :timestamp, null: false)
    column("updated_at", :timestamp, null: false)

  -> references(name, foreign_key: true, type: :bigint, null: true)
    column("#{name}_id", type, null: null)

  -> to_sql
    cols = @columns.map -> (c)
      Migration.sql_type(c.type, c.options)
      |> -> (type_sql) "#{c.name} #{type_sql}"
    "CREATE TABLE #{@name} (\n  #{cols.join(',\n  ')}\n)"


+ ReversibleBlock
  rw :up_block
  rw :down_block

  -> up(&block)   = @up_block = block
  -> down(&block) = @down_block = block
