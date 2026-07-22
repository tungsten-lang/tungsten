# PG::Types::JSONB — PostgreSQL jsonb type
# OID: 3802, maps to Tungsten Hash/Array via JSON parsing

in Tungsten:PG:Types

+ JSONB < PGType
  ro :oid { 3802 }
  ro :name { "jsonb" }

  [pure]
  -> decode(value)
    case value
      String => JSON.parse(value)
      =>       value

  [pure]
  -> encode(value)
    case value
      String => value  # assume already JSON
      =>       JSON.encode(value)

  [pure]
  -> sql_type
    "JSONB"
