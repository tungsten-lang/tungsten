# Strict parsing helpers for Metaflip's public command-line interface.
#
# String#to_i accepts an initial numeric prefix and may produce a boxed integer
# outside the i64 range.  Neither behavior is suitable at the CLI boundary:
# misspelled and overflowing resource limits must be rejected before campaign
# defaults or clamps can turn them into plausible-looking values.

-> ffcli_decimal_digit(character) (String) i64
  return 0 if character == "0"
  return 1 if character == "1"
  return 2 if character == "2"
  return 3 if character == "3"
  return 4 if character == "4"
  return 5 if character == "5"
  return 6 if character == "6"
  return 7 if character == "7"
  return 8 if character == "8"
  return 9 if character == "9"
  0 - 1

# Parse exactly one optional ASCII sign followed by one or more ASCII decimal
# digits.  Accumulating negatively leaves room for INT64_MIN, whose positive
# magnitude is not representable in i64.
-> ffcli_parse_i64(text, output) (String i64[]) i64
  if output.size() < 1 || text.size() < 1
    return 0

  cursor = 0 ## i64
  negative = 0 ## i64
  first = text.slice(0, 1)
  if first == "-"
    negative = 1
    cursor = 1
  elsif first == "+"
    cursor = 1
  if cursor >= text.size()
    return 0

  limit = 0 - 9223372036854775807 ## i64
  if negative != 0
    limit = 0 - 9223372036854775807 - 1
  multiplication_limit = limit / 10 ## i64
  value = 0 ## i64
  while cursor < text.size()
    digit = ffcli_decimal_digit(text.slice(cursor, 1)) ## i64
    if digit < 0 || value < multiplication_limit
      return 0
    value *= 10
    if value < limit + digit
      return 0
    value -= digit
    cursor += 1

  if negative == 0
    value = 0 - value
  output[0] = value
  1

-> ffcli_parse_unsigned_i64(text, output) (String i64[]) i64
  if text.size() < 1 || text.starts_with?("+") || text.starts_with?("-")
    return 0
  if ffcli_parse_i64(text, output) == 0 || output[0] < 0
    return 0
  1

-> ffcli_require_i64(option, text) (String String) i64
  parsed = i64[1]
  if ffcli_parse_i64(text, parsed) == 0
    << "metaflip: invalid integer for " + option + ": " + text
    exit(2)
  parsed[0]

-> ffcli_parse_square_tensor(text) (String) i64
  normalized = text.downcase
  if normalized.starts_with?("x") || normalized.ends_with?("x")
    return 0
  parts = normalized.split("x")
  if parts.size() != 2
    return 0
  left = i64[1]
  right = i64[1]
  if ffcli_parse_unsigned_i64(parts[0], left) == 0 || ffcli_parse_unsigned_i64(parts[1], right) == 0
    return 0
  if left[0] != right[0]
    return 0
  left[0]

-> ffcli_parse_scaled_moves(text) (String) i64
  normalized = text.strip().downcase
  factor = 1 ## i64
  number = normalized
  if normalized.ends_with?("k")
    factor = 1000
    number = normalized.slice(0, normalized.size() - 1)
  elsif normalized.ends_with?("m")
    factor = 1000000
    number = normalized.slice(0, normalized.size() - 1)
  elsif normalized.ends_with?("b")
    factor = 1000000000
    number = normalized.slice(0, normalized.size() - 1)

  if number.starts_with?(".") || number.ends_with?(".")
    return 0 - 1
  parts = number.split(".")
  if parts.size() < 1 || parts.size() > 2
    return 0 - 1
  whole_output = i64[1]
  if ffcli_parse_unsigned_i64(parts[0], whole_output) == 0
    return 0 - 1
  whole = whole_output[0] ## i64
  maximum = 9223372036854775807 ## i64
  if whole > maximum / factor
    return 0 - 1
  value = whole * factor ## i64

  if parts.size() == 2
    fraction_text = parts[1]
    if fraction_text.size() < 1 || fraction_text.size() > 3
      return 0 - 1
    fraction_output = i64[1]
    if ffcli_parse_unsigned_i64(fraction_text, fraction_output) == 0
      return 0 - 1
    denominator = 1 ## i64
    i = 0 ## i64
    while i < fraction_text.size()
      denominator *= 10
      i += 1
    contribution = fraction_output[0] * factor / denominator ## i64
    if contribution > maximum - value
      return 0 - 1
    value += contribution
  if value < 1
    return 0 - 1
  value

-> ffcli_parse_move_portfolio(text, output) (String i64[]) i64
  parts = text.split(",")
  if parts.size() != 4 || output.size() < 4
    return 0
  i = 0 ## i64
  while i < 4
    value = ffcli_parse_scaled_moves(parts[i]) ## i64
    if value < 1
      return 0
    output[i] = value
    i += 1
  1
