# PG::Types::Numeric — PostgreSQL numeric/decimal type
# OID: 1700, arbitrary precision decimal
# Maps to Tungsten Decimal

in Tungsten:PG:Types

+ Numeric < PGType
  ro :oid { 1700 }
  ro :name { "numeric" }

  [pure]
  -> decode(value)
    case value
      "NaN"       => Float.nan
      "Infinity"  => Float.infinity
      "-Infinity" => Float.negative_infinity
      =>           Decimal.new(value.to_s)

  [pure]
  -> encode(value)
    value.to_s

  [pure]
  -> sql_type(precision: nil, scale: nil)
    if precision && scale
      "NUMERIC(#{precision}, #{scale})"
    elsif precision
      "NUMERIC(#{precision})"
    else
      "NUMERIC"
