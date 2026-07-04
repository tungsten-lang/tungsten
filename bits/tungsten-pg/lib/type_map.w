# PG type mapping — maps PostgreSQL OIDs to Tungsten type decoders
# This is the bridge between raw PostgreSQL wire data and Tungsten values.

in Tungsten:PG

use types

# Base class for all PG types
+ PGType
  ro :oid
  ro :name

  -> decode(value) = value
  -> encode(value) = value.to_s
  -> sql_type      = @name.upcase


# Type map — registry of OID-to-decoder mappings
+ TypeMap
  ro :types

  -> new
    @types = {}

  -> .default
    map = self.new
    map.register(Types:Integer.new)
    map.register(Types:Text.new)
    map.register(Types:Boolean.new)
    map.register(Types:JSONB.new)
    map.register(Types:UUID.new)
    map.register(Types:Timestamp.new)
    map.register(Types:Timestamptz.new)
    map.register(Types:Numeric.new)
    map

  -> register(type)
    @types[type.oid] = type
    self

  -> decode(value, oid)
    return nil if value.nil?
    type = @types[oid]
    if type
      type.decode(value)
    else
      value  # fallback: return raw string

  -> encode(value)
    case value
      nil     => nil
      Bool    => Types:Boolean.new.encode(value)
      Int     => value.to_s
      Float   => value.to_s
      String  => value
      Time    => Types:Timestamp.new.encode(value)
      Hash    => Types:JSONB.new.encode(value)
      Array   => Types:JSONB.new.encode(value)
      =>       value.to_s

  -> type_for_oid(oid)
    @types[oid]

  -> type_for_name(name)
    @types.values.find(t -> t.name == name)


+ DecodeError < StandardError
+ EncodeError < StandardError
+ TypeError   < StandardError
+ RangeError  < StandardError
