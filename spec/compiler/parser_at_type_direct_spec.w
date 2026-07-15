# Focused semantic coverage for Parser's current-token type test. The isolated
# direct-helper trial keeps Parser#at_type? as a public compatibility wrapper
# while routing the parser's own grammar sites to a top-level helper.

use ../../compiler/lib/parser

-> check(name, got, want)
  if got != want
    << "FAIL parser at_type " + name + " got=" + got.to_s() + " want=" + want.to_s()
    exit(1)
  << "PASS parser at_type " + name

-> after_array(value)
  values = [value]
  values[0]

-> packed_type(type_id, offset = 0, length = 1, tagged = false)
  bits = type_id * 274877906944 + length * 67108864 + offset * 4
  if tagged
    # Real lexical-token tag. Values with this high bit materialize as BigInt
    # after Array storage, matching the parser's production token path.
    bits = bits - 1125899906842624
  after_array(bits)

+ ParserAtTypeProbe < Parser
  # Avoid Parser#new's unrelated location-table registry: at_type? and the
  # small token predicates below need only @current_packed.
  -> new(@current_packed)

  -> set_packed(value)
    @current_packed = value
    self

+ ParserAtTypeInheritedProbe < ParserAtTypeProbe
  -> inherited_marker
    true

+ ParserAtTypeOverrideProbe < ParserAtTypeProbe
  -> at_type?(type_id)
    type_id == 999

small = ParserAtTypeProbe.new(packed_type(7, 1, 3))
check("small true", small.at_type?(7), true)
check("small adjacent false", small.at_type?(6), false)

high = ParserAtTypeInheritedProbe.new(packed_type(255, 16777215, 4095, true))
check("tagged BigInt true", high.at_type?(255), true)
check("tagged BigInt false", high.at_type?(254), false)

# Offset and length occupy neighboring packed fields and must not affect the
# decoded type, including at their maximum representable values.
same_type = ParserAtTypeProbe.new(packed_type(31, 16777215, 4095, true))
check("max neighboring fields", same_type.at_type?(31), true)

zero = ParserAtTypeProbe.new(0)
check("zero token type", zero.at_type?(0), true)
check("zero token nonzero type", zero.at_type?(1), false)

predicates = ParserAtTypeProbe.new(packed_type(T_MINUS, 9, 2, true))
check("minus predicate", predicates.minus_token?(), true)
check("minus is not star", predicates.star_token?(), false)
predicates.set_packed(packed_type(T_STAR, 10, 1, true))
check("star predicate", predicates.star_token?(), true)
check("star is not minus", predicates.minus_token?(), false)
predicates.set_packed(packed_type(T_NAME, 11, 4, true))
check("name-or-constant name", predicates.at_name_or_constant?(), true)
predicates.set_packed(packed_type(T_CONSTANT, 12, 5, true))
check("name-or-constant constant", predicates.at_name_or_constant?(), true)
predicates.set_packed(packed_type(T_ID, 13, 2, true))
check("name-or-constant rejection", predicates.at_name_or_constant?(), false)

# The compatibility method remains an ordinary virtual method. The parser's
# internal direct calls deliberately rely on Parser being final-in-practice;
# this check guards only the public dispatch behavior promised by the wrapper.
override = ParserAtTypeOverrideProbe.new(packed_type(T_MINUS, 0, 1, true))
check("public override true", override.at_type?(999), true)
check("public override false", override.at_type?(T_MINUS), false)

<< "PASS parser at_type direct-helper semantics"
