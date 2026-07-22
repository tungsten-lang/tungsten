# PG::Types::Timestamp — PostgreSQL timestamp / timestamptz types
# OID: 1114 (timestamp), 1184 (timestamptz)
# Maps to Tungsten Time

in Tungsten:PG:Types

+ Timestamp < PGType
  ro :oid { 1114 }
  ro :name { "timestamp" }

  # ISO 8601 format for parsing
  ISO_FORMAT = "%Y-%m-%d %H:%M:%S"

  [pure]
  -> decode(value)
    case value
      "epoch"     => Time.at(0)
      "infinity"  => Time.infinity
      "-infinity" => Time.negative_infinity
      "now"       => Time.now
      String      => Time.parse(value)
      =>           value

  [pure]
  -> encode(value)
    case value
      Time   => value.strftime(ISO_FORMAT)
      String => value
      =>      value.to_s

  [pure]
  -> sql_type
    "TIMESTAMP"


+ Timestamptz < Timestamp
  ro :oid { 1184 }
  ro :name { "timestamptz" }

  ISO_TZ_FORMAT = "%Y-%m-%d %H:%M:%S%z"

  [pure]
  -> encode(value)
    case value
      Time   => value.utc.strftime(ISO_TZ_FORMAT)
      String => value
      =>      value.to_s

  [pure]
  -> sql_type
    "TIMESTAMPTZ"
