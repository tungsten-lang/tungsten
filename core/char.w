# Char — Unicode scalar value.
#
# Literals:
#   :-A      # ASCII character literal
#   :-/      # ASCII punctuation
#   U+221E   # Unicode scalar literal
+ Char
  is Comparable

  -> new(codepoint)

  # Identity / conversion
  -> codepoint
  -> ord
  -> to_i
  -> chr
  -> to_s
  -> inspect
  -> unicode_escape
  -> uplus
  -> hex
  -> bytes
  -> byte_size
  -> length
  -> size
  -> empty?
  -> chars
  -> codepoints

  # Ordering / stepping by Unicode scalar value.
  -> <=>(other)
  -> succ
  -> next
  -> pred
  -> prev
  -> +(offset)
  -> -(other)

  # Unicode shape.
  -> ascii?
  -> latin1?
  -> bmp?
  -> astral?
  -> valid?
  -> noncharacter?
  -> category
  -> general_category
  -> name
  -> unicode_name

  # Classification.
  -> letter?
  -> alphabetic?
  -> alpha?
  -> mark?
  -> number?
  -> digit?
  -> alnum?
  -> lowercase?
  -> lower?
  -> uppercase?
  -> upper?
  -> titlecase?
  -> whitespace?
  -> space?
  -> control?
  -> printable?
  -> punctuation?
  -> punct?
  -> symbol?
  -> separator?
  -> hex_digit?
  -> xdigit?
  -> id_start?
  -> id_continue?

  # Case mapping. A mapping that expands to multiple scalars returns String.
  -> upcase
  -> uppercase
  -> downcase
  -> lowercase
  -> titlecase
  -> casefold
  -> swapcase
