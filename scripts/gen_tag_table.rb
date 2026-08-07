#!/usr/bin/env ruby
# frozen_string_literal: true

# B3: generate the exact-tag overload-gate table in compiler/lib/lowering/types.w
# from the RUNTIME relation `w_value_is_a`, never from w_dispatch_key (a different
# many-to-one relation that can match perfectly and still be wrong — `Int` is
# tag-injective yet `is_a?(v, "Int")` is true for BigInt, Signed and Unsigned).
#
# Method: compile and run a probe program that, for a battery of representative
# values of every constructible runtime shape, prints the value's NaN-box tag
# facts (hi16, low nibble, payload>=0x10) and `v.is_a?(name)` for every
# candidate name. A name is admitted only when one tag-test shape reproduces
# the is_a? column EXACTLY across the whole battery AND the column has at
# least one positive witness (an all-false column would vacuously match an
# unpopulated tag — thin coverage must fail closed, not admit).
#
# Shapes modeled (B3): :top_tag ((bits & 0xFFFF...) == tag), :low_nibble
# (hi16==0, payload>=0x10, low nibble == subtag). The third shape (:gen_type,
# a dependent type-byte load) cannot be probed portably from source and no
# candidate needs it today; a name requiring it stays unadmitted.
#
# Usage:
#   ruby scripts/gen_tag_table.rb --check   # verify types.w block is current (CI)
#   ruby scripts/gen_tag_table.rb --write   # regenerate the block in place
#
# Expected result (asserted below): exactly {BigInt => top_tag 0xFFF8}. If the
# battery ever admits an ancestor name (Int, Number, ...) or drops BigInt, the
# script aborts rather than writing a wrong table.

require "tmpdir"

ROOT = File.expand_path("..", __dir__)
TYPES_W = File.join(ROOT, "compiler", "lib", "lowering", "types.w")
INTERP_W = File.join(ROOT, "compiler", "lib", "interpreter.w")
BEGIN_MARK = "# --- BEGIN GENERATED TAG TABLE (scripts/gen_tag_table.rb) ---"
END_MARK = "# --- END GENERATED TAG TABLE ---"

CANDIDATE_NAMES = %w[
  BigInt Int Integer Real Number Float Decimal String Symbol Array Hash Boolean Range Regex
].freeze

# Only allowlisted names may enter the table at all: a name that happens to be
# tag-pure across the battery (Hash, Range, Regex, ...) is still kept on the
# ancestry path until someone proves the equivalence holds for shapes the
# battery cannot construct AND a beneficiary exists. Empirical match is
# necessary, never sufficient.
MAY_ADMIT = %w[BigInt].freeze

# Names that must NEVER pass even the empirical filter — each has a verified
# counterexample IN THE BATTERY (multi-arm membership in
# w_primitive_is_a_type_name, or tower ancestry: a BigInt is_a? Int/Integer/
# Real/Number, a Symbol is not a String yet shares its tag, ...). If one of
# these is empirically admitted, the battery has rotted and the run must fail
# loudly instead of shipping a wrong table.
MUST_EXCLUDE = %w[Int Integer Real Number Float Decimal String Symbol Boolean].freeze

# Excluded a priori, no in-battery counterexample possible: `Array` is also
# true for SmallArray (subtag 9) and packed body arrays, but neither shape is
# portably constructible from probe source (stack-promotion demotes escaping
# `i32[N]` locals back to WArray). Kept out of MUST_EXCLUDE so their vacuous
# empirical match doesn't read as battery rot; kept out of MAY_ADMIT so they
# can never ship.
UNFALSIFIABLE = %w[Array].freeze

MUST_ADMIT = %w[BigInt].freeze

PROBE = <<~WPROBE
  -> probe(label, v)
    bits = wvalue_bits(v)
    hi = (bits >> 48) & 65535
    nib = bits & 15
    pge = (bits & 281474976710655) >= 16 ? 1 : 0
    line = "" + label + "\\t" + hi.to_s() + "\\t" + nib.to_s() + "\\t" + pge.to_s()
    names = [#{CANDIDATE_NAMES.map { |n| "\"#{n}\"" }.join(", ")}]
    i = 0
    while i < names.size()
      n = names[i]
      line = line + "\\t" + n + "=" + (v.is_a?(n) ? "1" : "0")
      i += 1
    << line

  + GtFoo
    -> ping
      1

  + GtBar < GtFoo
    -> pong
      2

  probe("int_zero", 0)
  probe("int_one", 1)
  probe("int_neg", 0 - 1)
  probe("int_i48_max", 140737488355327)
  probe("int_i48_min", 0 - 140737488355328)
  big = 10 ** 30
  probe("big_pos", big)
  nb = 0 - big
  probe("big_neg", nb)
  probe("big_flip", nb.abs)
  probe("big_multi", big * big)
  probe("float", 2.5)
  probe("float_neg", 0.0 - 2.5)
  probe("float_huge", 1.0e300)
  probe("decimal", 2.5.to_d)
  probe("string", "abc")
  probe("string_empty", "")
  probe("symbol", :sym)
  probe("array", [1, 2, 3])
  probe("array_empty", [])
  probe("array_str", ["a"])
  probe("hash", {a: 1})
  probe("range", (1..3))
  probe("regex", /ab+/)
  f = ->(x) x + 1
  probe("closure", f)
  probe("instance", GtFoo.new)
  probe("instance_sub", GtBar.new)
  probe("class_obj", GtFoo)
  probe("bool_true", true)
  probe("bool_false", false)
WPROBE

def run_probe
  rows = nil
  Dir.mktmpdir("gen_tag_table") do |dir|
    src = File.join(dir, "probe.w")
    bin = File.join(dir, "probe_bin")
    File.write(src, PROBE)
    out = `cd #{ROOT} && bin/tungsten -o #{bin} #{src} 2>&1`
    abort("gen_tag_table: probe compile failed:\n#{out}") unless $?.success?
    raw = `#{bin} 2>&1`
    abort("gen_tag_table: probe run failed:\n#{raw}") unless $?.success?
    rows = raw.lines.map(&:chomp).reject(&:empty?).map do |line|
      label, hi, nib, pge, *pairs = line.split("\t")
      isa = pairs.to_h { |p| k, v = p.split("="); [k, v == "1"] }
      { label: label, hi: hi.to_i, nib: nib.to_i, pge: pge.to_i == 1, isa: isa }
    end
  end
  abort("gen_tag_table: probe emitted no rows") if rows.nil? || rows.empty?
  missing = rows.reject { |r| r[:isa].keys.sort == CANDIDATE_NAMES.sort }
  abort("gen_tag_table: malformed probe rows: #{missing.map { |r| r[:label] }}") unless missing.empty?
  rows
end

def signed64(u)
  u >= 0x8000_0000_0000_0000 ? u - 0x1_0000_0000_0000_0000 : u
end

def admitted_entries(rows)
  entries = {}
  CANDIDATE_NAMES.each do |name|
    col = rows.map { |r| r[:isa][name] }
    next unless col.any? # no positive witness => fail closed

    # :top_tag over every populated hi16 tag value
    rows.map { |r| r[:hi] }.uniq.select { |t| t >= 0xFFF1 }.each do |t|
      if rows.all? { |r| (r[:hi] == t) == r[:isa][name] }
        entries[name] = { shape: :top_tag, hi: t }
        break
      end
    end
    next if entries.key?(name)

    # :low_nibble over every populated object subtag
    (0..0xF).each do |s|
      if rows.all? { |r| (r[:hi].zero? && r[:pge] && r[:nib] == s) == r[:isa][name] }
        entries[name] = { shape: :low_nibble, nib: s }
        break
      end
    end
  end
  entries
end

def render_block(entries)
  lines = []
  lines << BEGIN_MARK
  lines << "-> overload_exact_tag_entry(name)"
  lines << "  # tag/mask are the signed-i64 spellings of the uint64 bit patterns"
  lines << "  # (0xFFF8000000000000 and 0xFFFF000000000000)."
  entries.sort.each do |name, e|
    abort("gen_tag_table: no emitter for shape #{e[:shape]}") unless e[:shape] == :top_tag
    tag = signed64(e[:hi] << 48)
    lines << "  if name == \"#{name}\""
    lines << "    return {shape: :top_tag, tag: \"#{tag}\", mask: \"-281474976710656\"}"
  end
  lines << "  nil"
  lines << END_MARK
  lines.join("\n")
end

def current_block(path)
  text = File.read(path)
  m = text.match(/^#{Regexp.escape(BEGIN_MARK)}$.*?^#{Regexp.escape(END_MARK)}$/m)
  abort("gen_tag_table: markers not found in #{path}") unless m
  [text, m[0]]
end

mode = ARGV[0] || "--check"
rows = run_probe
empirical = admitted_entries(rows)

rotten = empirical.keys & MUST_EXCLUDE
abort("gen_tag_table: battery rot — empirically admitted excluded names #{rotten} (add counterexample values)") unless rotten.empty?
dropped = MUST_ADMIT - empirical.keys
abort("gen_tag_table: battery rot — expected admissions missing: #{dropped}") unless dropped.empty?

entries = empirical.select { |name, _| MAY_ADMIT.include?(name) }
suppressed = empirical.keys - entries.keys - UNFALSIFIABLE
puts "gen_tag_table: tag-pure in battery but not allowlisted: #{suppressed.join(", ")}" unless suppressed.empty?

fresh = render_block(entries)
text, existing = current_block(TYPES_W)

# The interpreter mirror is a deliberate hand-copy (no shared module); verify
# its literals still match the one generated entry so the copies cannot drift
# silently. Extend this check when the table grows.
if entries.key?("BigInt")
  interp = File.read(INTERP_W)
  unless interp.include?("& 65535) != 65528")
    abort("gen_tag_table: interpreter.w hand-copied BigInt tag literals not found — mirror has drifted")
  end
end

case mode
when "--check"
  if existing == fresh
    puts "gen_tag_table: OK (#{entries.size} entries: #{entries.keys.join(", ")})"
  else
    warn "gen_tag_table: STALE — types.w table differs from generated table. Run with --write."
    warn "--- generated ---\n#{fresh}\n--- in types.w ---\n#{existing}"
    exit 1
  end
when "--write"
  File.write(TYPES_W, text.sub(existing, fresh))
  puts "gen_tag_table: wrote #{entries.size} entries (#{entries.keys.join(", ")})"
else
  abort("usage: gen_tag_table.rb [--check|--write]")
end
