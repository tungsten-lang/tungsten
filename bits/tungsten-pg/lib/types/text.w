# PG::Types::Text — PostgreSQL text type
# OID: 25, maps to Tungsten String (no length limit)

in Tungsten:PG:Types

+ Text < PGType
  ro :oid { 25 }
  ro :name { "text" }

  [pure]
  -> decode(value)
    value.to_s

  [pure]
  -> encode(value)
    value.to_s

  [pure]
  -> sql_type
    "TEXT"
