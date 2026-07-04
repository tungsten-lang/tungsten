# frozen_string_literal: true

require "tungsten"

# Property-style test: for every atomic unit in UNIT_TABLE, the canonical
# string form (`1 <unit>`.to_s) must lex and parse back to an equal Quantity.
# This locks in the contract between the formatter and the lexer/parser.
RSpec.describe "Unit round-trip stability" do
  # Easter-egg outputs that intentionally don't round-trip — display a
  # human-readable approximation rather than the literal value.
  EXEMPT_FROM_ROUNDTRIP = Set.new(%w[
    barn\ megaparsec
  ]).freeze

  Tungsten::Units::UNIT_TABLE.each_key do |sym|
    next if EXEMPT_FROM_ROUNDTRIP.include?(sym)

    it "round-trips '1 #{sym}'" do
      q = Tungsten.run("1 #{sym}")
      next unless q.is_a?(Tungsten::Quantity)

      s = q.to_s
      q2 = Tungsten.run(s)
      expect(q2).to be_a(Tungsten::Quantity), "could not re-parse #{s.inspect}"
      expect(q).to eq(q2), "1 #{sym} → #{s.inspect} → re-parsed to #{q2.inspect}"
    end
  end

  describe "easter eggs (exempted)" do
    it "barn megaparsec displays as ≈π mL and is not expected to round-trip" do
      q = Tungsten.run("1 barn megaparsec")
      expect(q.to_s).to eq("≈π mL")
    end
  end
end
