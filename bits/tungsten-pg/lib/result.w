# PG::Result — wraps a PostgreSQL result set
# Provides iteration, column metadata, and type-decoded rows.

in Tungsten:PG

+ Result
  ro :raw
  ro :type_map
  ro :fields
  ro :rows

  -> new(@raw, @type_map)
    @fields = parse_fields
    @rows   = decode_rows

  # --- Iteration ---

  -> each(&block)
    @rows.each(&block)
    self

  -> map(&block)
    @rows.map(&block)

  -> select(&block)
    @rows.select(&block)

  -> reject(&block)
    @rows.reject(&block)

  -> flat_map(&block)
    @rows.flat_map(&block)

  -> each_with_index(&block)
    @rows.each_with_index(&block)

  -> reduce(initial, &block)
    @rows.reduce(initial, &block)

  # --- Access ---

  -> first
    @rows.first

  -> last
    @rows.last

  -> [](index)
    @rows[index]

  -> length
    @rows.size

  -> count = length

  -> empty?
    @rows.empty?

  -> any?(&block)
    if block
      @rows.any?(&block)
    else
      !empty?

  # --- Column metadata ---

  -> columns
    @fields.map(f -> f.name)

  -> column_types
    @fields.map(f -> f.type_oid)

  -> field_index(name)
    @fields.find_index(f -> f.name == name.to_s)

  # --- Conversion ---

  -> to_a
    @rows

  -> to_json
    @rows |> JSON.encode

  # Return rows as arrays instead of hashes
  -> values
    @raw.map -> (raw_row)
      raw_row.map_with_index -> (value, i)
        @type_map.decode(value, @fields[i].type_oid)

  # Single column as flat array
  -> pluck(column)
    @rows.map(row -> row[column])

  # Group rows by a column value
  -> group_by(column)
    @rows.group_by(row -> row[column])

  # --- Status ---

  -> status
    Native.pg_result_status(@raw)

  -> command_tag
    Native.pg_cmd_tag(@raw)

  -> affected_rows
    Native.pg_cmd_tuples(@raw).to_i

  # --- Internal ---

  -> parse_fields
    Native.pg_nfields(@raw).times.map -> (i)
      Field.new(
        name:     Native.pg_fname(@raw, i),
        type_oid: Native.pg_ftype(@raw, i),
        index:    i
      )

  -> decode_rows
    Native.pg_ntuples(@raw).times.map -> (row_idx)
      row = {}
      @fields.each -> (field)
        raw_value = Native.pg_getvalue(@raw, row_idx, field.index)
        row[field.name.to_sym] = if raw_value.nil?
          nil
        else
          @type_map.decode(raw_value, field.type_oid)
      row


+ Field
  ro :name
  ro :type_oid
  ro :index

  -> new(@name, @type_oid, @index)
