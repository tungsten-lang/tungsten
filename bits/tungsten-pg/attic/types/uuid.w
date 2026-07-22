# PG::Types::UUID — PostgreSQL uuid type
# OID: 2950, maps to Tungsten String (formatted as UUID)

in Tungsten:PG:Types

+ UUID < PGType
  ro :oid { 2950 }
  ro :name { "uuid" }

  UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  [pure]
  -> decode(value)
    value.to_s.downcase

  [pure]
  -> encode(value)
    str = value.to_s.downcase
    unless str.match?(UUID_PATTERN)
      <! EncodeError.new("Invalid UUID: #{value}")
    str

  [pure]
  -> sql_type
    "UUID"

  [pure]
  -> generate
    Random.uuid
