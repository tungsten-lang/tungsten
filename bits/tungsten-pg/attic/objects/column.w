# PG::Objects::Column — represents a column in a PostgreSQL table
# Provides type info, constraints, and SQL generation.

in Tungsten:PG:Objects

+ Column
  ro :name
  ro :type
  ro :nullable
  ro :default
  ro :position
  ro :primary_key

  -> new(name:, type:, nullable: true, default: nil, position: 0, primary_key: false)
    @name        = name
    @type        = type
    @nullable    = nullable
    @default     = default
    @position    = position
    @primary_key = primary_key

  -> nullable?    = @nullable
  -> primary_key? = @primary_key
  -> has_default?  = !@default.nil?

  -> to_sql
    parts = ["#{@name} #{@type}"]
    parts.push("PRIMARY KEY") if @primary_key
    parts.push("NOT NULL") unless @nullable
    parts.push("DEFAULT #{@default}") if @default
    parts.join(" ")

  -> inspect
    "#<Column #{@name} #{@type}#{' NOT NULL' unless @nullable}>"
