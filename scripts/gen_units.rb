#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates unit lookup tables from data/units.tsv for both:
#   1. compiler/lib/lowering/literals.w  (Tungsten case/when)
#   2. runtime/runtime.c (C initializer)
#
# Usage:
#   ruby scripts/gen_units.rb              # prints both outputs
#   ruby scripts/gen_units.rb --tungsten   # Tungsten case/when only
#   ruby scripts/gen_units.rb --c          # C initializer only
#   ruby scripts/gen_units.rb --write      # overwrite both files in-place
#   ruby scripts/gen_units.rb --check      # verify generated files are current

ROOT = File.expand_path("..", __dir__)
TSV_PATH = File.join(ROOT, "data/units.tsv")

Unit = Struct.new(:id, :name, :category, keyword_init: true)

def load_units
  units = []
  File.readlines(TSV_PATH, encoding: "utf-8").each do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")

    parts = line.split("\t")
    units << Unit.new(id: parts[0].to_i, name: parts[1], category: parts[2])
  end
  units.sort_by(&:id)
end

# Characters that can appear in a lexer-scanned unit suffix (alpha + / + digits after alpha).
# Units with spaces (like "fl oz") or special Unicode can only come from the C table,
# not from the Tungsten lexer lookup. We include them anyway for completeness.
def lexer_scannable?(name)
  name.match?(/\A[\p{L}0-9\/%·°\^⁰¹²³⁴⁵⁶⁷⁸⁹]+\z/)
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

def generate_tungsten(units)
  lines = []
  lines << "-> lookup_unit_id(ctx, raw_unit, node)"
  lines << "  # Materialize the scrutinee: node-field strings can be lexer slices, whose"
  lines << "  # WValue bits never equal the interned case keys in the switch_i64 dispatch."
  lines << "  unit = \"\" + raw_unit"
  lines << "  case unit"

  units.each do |u|
    # Only include units scannable by the stage lexer
    next unless lexer_scannable?(u.name)

    lines << "    \"#{u.name}\" => #{u.id}"
  end

  lines << "    => assign_custom_unit(ctx, unit, node)"
  lines << ""

  lines.join("\n")
end

def generate_c(units)
  lines = []
  lines << "static const char *unit_names[256] = {"

  # Group by category for readability
  current_category = nil
  units.each do |u|
    if u.category != current_category
      lines << "" if current_category
      current_category = u.category
      lines << "    /* #{u.id}-: #{current_category} */"
    end
    c_str = utf8_c_literal(u.name)
    lines << "    [#{u.id}] = \"#{c_str}\","
  end

  lines << "};"
  lines.join("\n")
end

# Conversion metadata (dimension vector + exact rational SI factor) comes
# from the Ruby reference implementation — the single source of truth for
# unit semantics. Units it can't resolve linearly (offset units like °C,
# jokes like "heap", custom) get the {0,0} no-conversion sentinel: they
# still display, but cross-unit arithmetic raises like before.
def generate_c_info(units)
  $LOAD_PATH.unshift File.join(ROOT, "implementations/ruby/lib")
  require "tungsten"

  lines = []
  # off_num/off_den carry the affine offset (SI = raw*num/den + off_num/off_den),
  # nonzero only for temperature scales (°C/°F/°R) — see quantity_convert.
  lines << "typedef struct { int8_t dim[8]; int64_t num; int64_t den; int64_t off_num; int64_t off_den; } WUnitInfo;"
  lines << "/* non-const: the custom region (140+) takes synthesized compound units at runtime */"
  lines << "static WUnitInfo unit_info[256] = {"

  units.each do |u|
    entry = "    [#{u.id}] = {{0,0,0,0,0,0,0,0}, 0, 0, 0, 1},"
    begin
      parsed = Tungsten::Units.parse(u.name)
      dim = parsed.dimension.to_a
      factor = parsed.factor
      offset = parsed.respond_to?(:offset) ? (parsed.offset || 0) : 0
      num = factor.is_a?(Rational) ? factor.numerator : factor
      den = factor.is_a?(Rational) ? factor.denominator : 1
      onum = offset.is_a?(Rational) ? offset.numerator : offset
      oden = offset.is_a?(Rational) ? offset.denominator : 1
      # A unit that fell through `Units.parse` to the unknown-unit catch-all
      # resolves to a custom pseudo-dimension whose base 8-vector is all zero
      # (e.g. the missing MWh/Torr, or joke units like PB). Its `to_a` is
      # indistinguishable from a real dimensionless unit, so the emit below
      # would write a *live* {dims=0, 1/1} row — making the unit silently
      # behave as a pure scalar (it vanishes in products, mismatches in sums)
      # instead of raising the no-conversion error. Keep the {0,0} sentinel for
      # these. Compound units carrying a real base projection (Hz → time⁻¹,
      # customs={cycle}) have a non-zero `to_a` and still emit a live row, so
      # frequency/activity conversions are unaffected.
      is_unconvertible_custom = parsed.dimension.respond_to?(:custom?) &&
                                parsed.dimension.custom? &&
                                dim.is_a?(Array) && dim.all?(&:zero?)
      if !is_unconvertible_custom && dim.is_a?(Array) && dim.size == 8 &&
         dim.all? { |d| d.is_a?(Integer) } &&
         num.is_a?(Integer) && den.is_a?(Integer) && den != 0 &&
         num.abs < (1 << 62) && den.abs < (1 << 62) &&
         onum.is_a?(Integer) && oden.is_a?(Integer) && oden != 0 &&
         onum.abs < (1 << 62) && oden.abs < (1 << 62)
        entry = "    [#{u.id}] = {{#{dim.join(',')}}, #{num}, #{den}, #{onum}, #{oden}},"
      end
    rescue StandardError
      # keep sentinel
    end
    lines << entry + " /* #{utf8_c_literal(u.name)} */"
  end

  lines << "};"
  lines.join("\n")
end

# Lexer-side membership test for space-separated quantities (`10 ft`):
# after a number + single space, an identifier that names a known unit makes
# the pair one QUANTITY token. `%` is excluded — it never follows a space.
def generate_lexer(units)
  # `%` never follows a space; `in` is the membership keyword (`x in (…)`)
  # and must not turn `3 in (...)` into 3 inches.
  scannable = units.select { |u| lexer_scannable?(u.name) && u.name != "%" && u.name != "in" }
  lines = []
  lines << "-> known_unit_name?(s)"
  scannable.each_slice(12) do |slice|
    lines << "  if s in (" + slice.map { |u| "\"#{u.name}\"" }.join(" ") + ")"
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

units = load_units

case ARGV[0]
when "--tungsten"
  puts generate_tungsten(units)
when "--c"
  puts generate_c(units)
when "--c-info"
  puts generate_c_info(units)
when "--lexer"
  puts generate_lexer(units)
when "--write"
  tungsten_code = generate_tungsten(units)
  c_code = generate_c(units)
  c_info_code = generate_c_info(units)
  lexer_code = generate_lexer(units)

  if replace_between(TUNGSTEN_FILE, TUNGSTEN_START, TUNGSTEN_END, tungsten_code)
    puts "Updated #{TUNGSTEN_FILE}"
  end

  if replace_between(LEXER_FILE, LEXER_START, LEXER_END, lexer_code)
    puts "Updated #{LEXER_FILE} (known_unit_name?)"
  end

  if replace_between(C_FILE, C_START, C_END, c_code)
    puts "Updated #{C_FILE}"
  end

  if replace_between(C_FILE, C_INFO_START, C_INFO_END, c_info_code)
    puts "Updated #{C_FILE} (unit_info)"
  end
when "--check"
  tungsten_code = generate_tungsten(units)
  c_code = generate_c(units)
  c_info_code = generate_c_info(units)
  lexer_code = generate_lexer(units)

  ok = true
  ok = check_between(TUNGSTEN_FILE, TUNGSTEN_START, TUNGSTEN_END, tungsten_code) && ok
  ok = check_between(LEXER_FILE, LEXER_START, LEXER_END, lexer_code) && ok
  ok = check_between(C_FILE, C_START, C_END, c_code) && ok
  ok = check_between(C_FILE, C_INFO_START, C_INFO_END, c_info_code) && ok

  if ok
    puts "Generated unit tables are up to date"
  else
    abort "Generated unit tables are stale; run ruby scripts/gen_units.rb --write"
  end
else
  puts "=== Tungsten (lowering/literals.w) ==="
  puts generate_tungsten(units)
  puts
  puts "=== C (runtime.c) ==="
  puts generate_c(units)
end
