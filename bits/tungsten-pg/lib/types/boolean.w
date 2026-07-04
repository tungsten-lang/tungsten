# PG::Types::Boolean — PostgreSQL boolean type
# OID: 16, maps to Tungsten Bool

in Tungsten:PG:Types

+ Boolean < PGType
  ro :oid { 16 }
  ro :name { "boolean" }

  [pure]
  -> decode(value)
    case value
      "t", "true", "1", "yes", "on" => true
      "f", "false", "0", "no", "off" => false
      true  => true
      false => false
      =>     <! DecodeError.new("Cannot decode boolean: #{value}")

  [pure]
  -> encode(value)
    if value then "t" else "f"

  [pure]
  -> sql_type
    "BOOLEAN"
