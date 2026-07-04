# PG::Types::Integer — PostgreSQL integer type (int4)
# OID: 23, maps to Tungsten Int

in Tungsten:PG:Types

+ Integer < PGType
  ro :oid { 23 }
  ro :name { "integer" }

  [pure]
  -> decode(value)
    value.to_i

  [pure]
  -> encode(value)
    value.to_s

  [pure]
  -> sql_type
    "INTEGER"

  -> validate(value)
    unless value.is_a?(Numeric)
      <! TypeError.new("Expected numeric, got #{value.class}")
    unless value >= -2147483648 && value <= 2147483647
      <! RangeError.new("Integer out of range: #{value}")
