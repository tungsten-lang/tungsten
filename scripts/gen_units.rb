#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates unit lookup tables from the stable legacy IDs in data/units.tsv
# plus the full Ruby reference registry for both:
#   1. compiler/lib/lowering/literals.w  (Tungsten case/when)
#   2. runtime/runtime.c (C initializer)
#
# Usage:
#   ruby scripts/gen_units.rb              # prints both outputs
#   ruby scripts/gen_units.rb --tungsten   # Tungsten case/when only
#   ruby scripts/gen_units.rb --c          # C initializer only
#   ruby scripts/gen_units.rb --manifest   # name<TAB>id<TAB>canonical for tests
#   ruby scripts/gen_units.rb --write      # overwrite both files in-place
#   ruby scripts/gen_units.rb --check      # verify generated files are current

ROOT = File.expand_path("..", __dir__)
TSV_PATH = File.join(ROOT, "data/units.tsv")

Unit = Struct.new(:id, :name, :category, keyword_init: true)
Registry = Struct.new(:units, :aliases, :custom_dimensions, keyword_init: true)

UNIT_CAPACITY = 4096
CUSTOM_UNIT_BASE = 2048

def load_legacy_units
  units = []
  File.readlines(TSV_PATH, encoding: "utf-8").each do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")

    parts = line.split("\t")
    units << Unit.new(id: parts[0].to_i, name: parts[1], category: parts[2])
  end
  units.sort_by(&:id)
end

# Preserve the compact legacy IDs, then append every canonical unit from the
# Ruby reference registry above the 8-bit inline range. Aliases share their
# canonical ID and therefore do not consume registry slots.
def load_registry
  legacy = load_legacy_units
  $LOAD_PATH.unshift File.join(ROOT, "implementations/ruby/lib")
  require "tungsten"

  units = legacy.dup
  unit_by_name = units.to_h { |u| [u.name, u] }
  canonical_names = Tungsten::Units::UNIT_TABLE.keys | Tungsten::Units::COMPOUND_DEFS.keys
  next_id = 256
  canonical_names.each do |name|
    next if unit_by_name.key?(name)
    raise "unit registry exceeds reserved custom-unit base" if next_id >= CUSTOM_UNIT_BASE

    category = Tungsten::Units::COMPOUND_DEFS.key?(name) ? "Ruby compound" : "Ruby registry"
    unit = Unit.new(id: next_id, name: name, category: category)
    units << unit
    unit_by_name[name] = unit
    next_id += 1
  end

  aliases = {}
  units.each { |u| aliases[u.name] = u.id }
  Tungsten::Units::UNIT_ALIASES.each do |name, canonical|
    target = unit_by_name[canonical]
    aliases[name] ||= target.id if target
  end

  custom_names = units.flat_map do |u|
    next [] if u.name == "%"
    Tungsten::Units.parse(u.name).dimension.customs.keys
  end.uniq.sort
  custom_dimensions = custom_names.each_with_index.to_h { |name, i| [name, i + 1] }

  Registry.new(units: units.sort_by(&:id), aliases: aliases,
               custom_dimensions: custom_dimensions)
end

def utf8_c_literal(str)
  bytes = str.encode("utf-8").bytes
  result = +""
  prev_was_hex_escape = false
  bytes.each do |b|
    is_hex_digit = (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46) ||
                   (b >= 0x61 && b <= 0x66)
    if b >= 0x20 && b <= 0x7E && b != 0x22 && b != 0x5C && !(prev_was_hex_escape && is_hex_digit)
      result << b.chr
      prev_was_hex_escape = false
    else
      result << format("\\x%02x", b)
      prev_was_hex_escape = true
    end
  end
  result
end

def generate_tungsten(registry)
  lines = []
  lines << "-> lookup_unit_id(ctx, raw_unit, node)"
  lines << "  # Materialize the scrutinee: node-field strings can be lexer slices, whose"
  lines << "  # WValue bits never equal the interned case keys in the switch_i64 dispatch."
  lines << "  unit = \"\" + raw_unit"
  lines << "  case unit"

  registry.aliases.sort.each do |name, id|
    lines << "    \"#{name}\" => #{id}"
  end

  lines << "    => assign_custom_unit(ctx, unit, node)"
  lines << ""

  canonical_by_id = registry.units.to_h { |unit| [unit.id, unit.name] }
  signature_by_id = canonical_by_id.transform_values do |name|
    dimension = Tungsten::Units.parse(name).dimension
    base = %i[length mass time current temperature substance luminosity information].map do |field|
      dimension.public_send(field)
    end
    custom = dimension.customs.sort.map { |tag, exponent| "#{tag}:#{exponent}" }.join(";")
    (base + [custom]).join(",")
  end

  lines << "# Compile-time-only dimension identity. Kept separate from unit ids: aliases"
  lines << "# and scaled units intentionally collapse to one physical signature."
  lines << "-> lookup_unit_static_signature(raw_unit)"
  lines << "  unit = \"\" + raw_unit"
  lines << "  case unit"
  registry.aliases.sort.each do |name, id|
    lines << "    \"#{name}\" => \"#{signature_by_id.fetch(id)}\""
  end
  lines << "    => nil"
  lines << ""

  lines.join("\n")
end

def generate_c(registry)
  lines = []
  lines << "#define W_UNIT_CAPACITY #{UNIT_CAPACITY}"
  lines << "#define W_UNIT_CUSTOM_BASE #{CUSTOM_UNIT_BASE}"
  lines << "static const char *unit_names[W_UNIT_CAPACITY] = {"

  # Group by category for readability
  current_category = nil
  registry.units.each do |u|
    if u.category != current_category
      lines << "" if current_category
      current_category = u.category
      lines << "    /* #{u.id}-: #{current_category} */"
    end
    c_str = utf8_c_literal(u.name)
    lines << "    [#{u.id}] = \"#{c_str}\","
  end

  lines << "};"
  lines << ""
  lines << "typedef struct { const char *name; int id; } WUnitAlias;"
  lines << "static const WUnitAlias unit_aliases[] = {"
  registry.aliases.sort.each do |name, id|
    lines << "    {\"#{utf8_c_literal(name)}\", #{id}},"
  end
  lines << "};"
  lines << "static int unit_lookup_id(const char *name) {"
  lines << "    int lo = 0, hi = (int)(sizeof(unit_aliases) / sizeof(unit_aliases[0])) - 1;"
  lines << "    while (lo <= hi) {"
  lines << "        int mid = lo + (hi - lo) / 2;"
  lines << "        int cmp = strcmp(name, unit_aliases[mid].name);"
  lines << "        if (cmp == 0) return unit_aliases[mid].id;"
  lines << "        if (cmp < 0) hi = mid - 1; else lo = mid + 1;"
  lines << "    }"
  lines << "    return -1;"
  lines << "}"
  lines.join("\n")
end

# Store a conversion factor as num/den × 10^scale. Exact rationals that fit
# retain their numerator and denominator. Very large/small values fall back to
# an 18-significant-digit decimal without passing through Float.
def compact_rational(value)
  value = value.rationalize if value.is_a?(Float)
  value = Rational(value)
  return [0, 1, 0] if value.zero?

  num = value.numerator
  den = value.denominator
  scale = 0
  while (num % 10).zero?
    num /= 10
    scale += 1
  end
  while (den % 10).zero?
    den /= 10
    scale -= 1
  end
  limit = 1 << 62
  return [num, den, scale] if num.abs < limit && den.abs < limit

  sign = num.negative? ? -1 : 1
  n = num.abs
  d = den.abs
  exponent = n.to_s.length - d.to_s.length
  too_small = exponent >= 0 ? n < d * 10**exponent : n * 10**(-exponent) < d
  exponent -= 1 if too_small
  digits = 18
  if exponent >= 0
    divisor = d * 10**exponent
    q, r = (n * 10**(digits - 1)).divmod(divisor)
  else
    divisor = d
    q, r = (n * 10**(digits - 1 - exponent)).divmod(divisor)
  end
  q += 1 if r * 2 >= divisor
  if q >= 10**digits
    q /= 10
    exponent += 1
  end
  scale = exponent - (digits - 1)
  while (q % 10).zero?
    q /= 10
    scale += 1
  end
  [sign * q, 1, scale]
end

# Conversion metadata (dimension vector, custom tag, and rational/decimal SI
# factor) comes from the Ruby reference implementation. Generation fails if
# any non-percent registry entry cannot be represented.
def generate_c_info(registry)
  lines = []
  # off_num/off_den carry the affine offset (SI = raw*num/den + off_num/off_den),
  # nonzero only for temperature scales (°C/°F/°R) — see quantity_convert.
  lines << "typedef struct { int8_t dim[8]; int16_t custom_id; int8_t custom_exp; int64_t num; int64_t den; int16_t factor_scale; int64_t off_num; int64_t off_den; } WUnitInfo;"
  lines << "static const char *custom_dimension_names[] = {"
  lines << "    NULL,"
  registry.custom_dimensions.sort_by { |_, id| id }.each do |name, _id|
    lines << "    \"#{utf8_c_literal(name)}\","
  end
  lines << "};"
  lines << "/* non-const: the custom region takes synthesized compound units at runtime */"
  lines << "static WUnitInfo unit_info[W_UNIT_CAPACITY] = {"

  registry.units.each do |u|
    entry = "    [#{u.id}] = {{0,0,0,0,0,0,0,0}, 0, 0, 0, 0, 0, 0, 1},"
    if u.name == "%"
      lines << entry + " /* % */"
      next
    end
    begin
      parsed = Tungsten::Units.parse(u.name)
      dim = parsed.dimension.to_a
      offset = parsed.respond_to?(:offset) ? (parsed.offset || 0) : 0
      num, den, factor_scale = compact_rational(parsed.factor)
      onum = offset.is_a?(Rational) ? offset.numerator : offset
      oden = offset.is_a?(Rational) ? offset.denominator : 1
      custom_name, custom_exp = parsed.dimension.customs.first
      custom_id = custom_name ? registry.custom_dimensions.fetch(custom_name) : 0
      custom_exp ||= 0
      valid = dim.is_a?(Array) && dim.size == 8 && dim.all? { |d| d.is_a?(Integer) } &&
              num.is_a?(Integer) && den.is_a?(Integer) && den != 0 &&
              num.abs < (1 << 62) && den.abs < (1 << 62) &&
              onum.is_a?(Integer) && oden.is_a?(Integer) && oden != 0 &&
              onum.abs < (1 << 62) && oden.abs < (1 << 62)
      raise "unrepresentable conversion metadata" unless valid
      entry = "    [#{u.id}] = {{#{dim.join(',')}}, #{custom_id}, #{custom_exp}, #{num}, #{den}, #{factor_scale}, #{onum}, #{oden}},"
    rescue StandardError => e
      raise "cannot generate unit #{u.name.inspect}: #{e.message}", e.backtrace
    end
    lines << entry + " /* #{utf8_c_literal(u.name)} */"
  end

  lines << "};"
  lines.join("\n")
end

# Lexer-side membership test for space-separated quantities (`10 ft`):
# after a number + single space, an identifier that names a known unit makes
# the pair one QUANTITY token. `%` is excluded — it never follows a space.
def generate_lexer(registry, function_name = "known_unit_name?")
  # `%` never follows a space; `in` is the membership keyword (`x in (…)`)
  # and must not turn `3 in (...)` into 3 inches.
  scannable = registry.aliases.keys.reject { |name| name == "%" || name == "in" }.sort
  lines = []
  lines << "-> #{function_name}(s)"
  scannable.each_slice(12) do |slice|
    lines << "  if s in (" + slice.map { |name| "\"#{name}\"" }.join(" ") + ")"
    lines << "    return true"
  end
  lines << "  false"
  lines << ""
  lines.join("\n")
end

# -- Markers for in-place replacement --

TUNGSTEN_FILE = File.join(ROOT, "compiler/lib/lowering/literals.w")
TUNGSTEN_START = "# --- BEGIN GENERATED: lookup_unit_id ---"
TUNGSTEN_END   = "# --- END GENERATED: lookup_unit_id ---"

LEXER_FILE = File.join(ROOT, "compiler/lib/lexer.w")
LEXER_START = "# --- BEGIN GENERATED: known_unit_name ---"
LEXER_END   = "# --- END GENERATED: known_unit_name ---"

REGEX_LEXER_FILE = File.join(ROOT, "languages/tungsten/lexers/known_units.w")
REGEX_LEXER_START = "# --- BEGIN GENERATED: regex_known_unit_name ---"
REGEX_LEXER_END   = "# --- END GENERATED: regex_known_unit_name ---"

C_FILE = File.join(ROOT, "runtime/runtime.c")
C_START = "/* --- BEGIN GENERATED: unit_names --- */"
C_END   = "/* --- END GENERATED: unit_names --- */"

C_INFO_START = "/* --- BEGIN GENERATED: unit_info --- */"
C_INFO_END   = "/* --- END GENERATED: unit_info --- */"

def replace_between(file, start_marker, end_marker, replacement)
  content = File.read(file, encoding: "utf-8")
  unless content.include?(start_marker)
    warn "WARNING: marker '#{start_marker}' not found in #{file}"
    return false
  end

  pattern = /#{Regexp.escape(start_marker)}.*?#{Regexp.escape(end_marker)}/m
  new_content = content.sub(pattern, "#{start_marker}\n#{replacement}\n#{end_marker}")
  File.write(file, new_content, encoding: "utf-8")
  true
end

def check_between(file, start_marker, end_marker, replacement)
  content = File.read(file, encoding: "utf-8")
  pattern = /#{Regexp.escape(start_marker)}.*?#{Regexp.escape(end_marker)}/m
  actual = content[pattern]
  expected = "#{start_marker}\n#{replacement}\n#{end_marker}"

  if actual == expected
    return true
  end

  if actual.nil?
    warn "Generated block missing in #{file}: #{start_marker}"
  else
    warn "Generated block is stale in #{file}: #{start_marker}"
  end
  false
end

# -- Main --

registry = load_registry

case ARGV[0]
when "--tungsten"
  puts generate_tungsten(registry)
when "--c"
  puts generate_c(registry)
when "--c-info"
  puts generate_c_info(registry)
when "--lexer"
  puts generate_lexer(registry)
when "--manifest"
  canonical_by_id = registry.units.to_h { |unit| [unit.id, unit.name] }
  registry.aliases.sort.each do |name, id|
    puts [name, id, canonical_by_id.fetch(id)].join("\t")
  end
when "--write"
  tungsten_code = generate_tungsten(registry)
  c_code = generate_c(registry)
  c_info_code = generate_c_info(registry)
  lexer_code = generate_lexer(registry)
  regex_lexer_code = generate_lexer(registry, "regex_known_unit_name?")

  if replace_between(TUNGSTEN_FILE, TUNGSTEN_START, TUNGSTEN_END, tungsten_code)
    puts "Updated #{TUNGSTEN_FILE}"
  end

  if replace_between(LEXER_FILE, LEXER_START, LEXER_END, lexer_code)
    puts "Updated #{LEXER_FILE} (known_unit_name?)"
  end

  if replace_between(REGEX_LEXER_FILE, REGEX_LEXER_START, REGEX_LEXER_END, regex_lexer_code)
    puts "Updated #{REGEX_LEXER_FILE} (regex_known_unit_name?)"
  end

  if replace_between(C_FILE, C_START, C_END, c_code)
    puts "Updated #{C_FILE}"
  end

  if replace_between(C_FILE, C_INFO_START, C_INFO_END, c_info_code)
    puts "Updated #{C_FILE} (unit_info)"
  end
when "--check"
  tungsten_code = generate_tungsten(registry)
  c_code = generate_c(registry)
  c_info_code = generate_c_info(registry)
  lexer_code = generate_lexer(registry)
  regex_lexer_code = generate_lexer(registry, "regex_known_unit_name?")

  ok = true
  ok = check_between(TUNGSTEN_FILE, TUNGSTEN_START, TUNGSTEN_END, tungsten_code) && ok
  ok = check_between(LEXER_FILE, LEXER_START, LEXER_END, lexer_code) && ok
  ok = check_between(REGEX_LEXER_FILE, REGEX_LEXER_START, REGEX_LEXER_END, regex_lexer_code) && ok
  ok = check_between(C_FILE, C_START, C_END, c_code) && ok
  ok = check_between(C_FILE, C_INFO_START, C_INFO_END, c_info_code) && ok

  if ok
    puts "Generated unit tables are up to date"
  else
    abort "Generated unit tables are stale; run ruby scripts/gen_units.rb --write"
  end
else
  puts "=== Tungsten (lowering/literals.w) ==="
  puts generate_tungsten(registry)
  puts
  puts "=== C (runtime.c) ==="
  puts generate_c(registry)
end
