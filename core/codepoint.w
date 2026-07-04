# Codepoint — compatibility name for a Unicode scalar value.
#
# Tungsten represents a concrete scalar as Char. U+NNNN literals and :-X
# character literals both report Char at runtime; Codepoint exists as a
# readable surface for APIs that talk specifically about scalar values.
+ Codepoint < Char
  -> new(value)
  -> valid?/1
  -> scalar?/1
  -> from_i/1
  -> to_char
