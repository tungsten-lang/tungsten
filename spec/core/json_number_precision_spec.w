# Long JSON numeric tokens must preserve precision on every engine.
-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# Long mantissas must reach the text-number fallback without overflowing the
# small-integer accumulator used only by short numeric tokens.
large = JSON.parse("\[123456789012345678901234567890,-123456789012345678901234567890,1814780882.1234567,0.1234567890123456789012345\]")
check("num.bigint.positive", large[0].to_s == "123456789012345678901234567890")
check("num.bigint.negative", large[1].to_s == "-123456789012345678901234567890")
check("num.timestamp.mantissa", large[2] == ~1814780882.1234567)
check("num.fraction.mantissa", large[3] == ~0.12345678901234568)
check("num.bigint.encode", JSON.encode(large[0]) == "123456789012345678901234567890")
