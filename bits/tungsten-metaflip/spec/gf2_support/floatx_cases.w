# Cases for lib/metaflip/gf2/floatx.w: exact double <-> decimal conversion,
# checked against Python's repr / float() / format() / round() on real bit
# patterns (fixtures/gf2_support/json/floats.tsv and decimals.tsv, made by
# gen_json_goldens.py).
use ../../lib/metaflip/gf2/floatx
use ../../lib/metaflip/gf2/textx

# The Float with this 16-digit hex bit pattern. (String#to_i(16) saturates at
# 2^63, so the two 32-bit halves are read separately.)
-> gf2_float_from_hex(text)
  high = text.slice(0, 8).to_i(16)
  low = text.slice(8, 8).to_i(16)
  Floatx.from_fields(high >= 2147483648, (high >> 20) & 2047, ((high & 1048575) << 32) | low)

# 16-digit hex bit pattern of a Float.
-> gf2_hex_of_float(x)
  fields = Floatx.fields(x)
  high = (fields[1] << 20) | (fields[2] >> 32)
  high = high | 2147483648 if fields[0]
  high.to_s(16).lpad(8, "0") + (fields[2] & 4294967295).to_s(16).lpad(8, "0")

-> gf2_tsv_rows(path)
  rows = []
  read_file(path).split("\n").each -> (line)
    rows.push(line.split("\t")) if line.size > 0
  rows

-> gf2_floatx_cases(t)
  dir = __DIR__ + "/../fixtures/gf2_support/json"

  # Python repr / '%.Nf' / '%.Ng' / '.N%' for finite doubles
  rows = gf2_tsv_rows(dir + "/floats.tsv")
  bad = 0
  places = [0, 1, 2, 4, 6]
  precisions = [1, 3, 6, 17]
  rows.each -> (c)
    x = gf2_float_from_hex(c[0])
    ok = Floatx.repr(x) == c[1]
    places.each_with_index -> (p, k)
      ok = false if c[2 + k] != "-" && Floatx.fixed(x, p) != c[2 + k]
    precisions.each_with_index -> (p, k)
      ok = false if Floatx.general(x, p) != c[7 + k]
    [0, 1].each_with_index -> (p, k)
      ok = false if c[11 + k] != "-" && Floatx.percent(x, p) != c[11 + k]
    ok = false if c[13] != "-" && Floatx.repr(Floatx.round(x, 2)) != c[13]
    if !ok
      bad += 1
      << "  float " + c[0] + " repr " + Floatx.repr(x) + " want " + c[1] if bad < 5
  t.eq("floats.tsv: repr, fixed, general, percent and round agree with Python (" + rows.size.to_s + " doubles)", bad, 0)

  t.eq("repr of common values", [Floatx.repr(Floatx.parse("0.1")), Floatx.repr(Floatx.parse("1e22")), Floatx.repr(Floatx.parse("100")), Floatx.repr(Floatx.parse("-0.0")), Floatx.repr(Floatx.parse("1e-5"))], ["0.1", "1e+22", "100.0", "-0.0", "1e-05"])
  t.eq("repr of the extremes", [Floatx.repr(Floatx.parse("5e-324")), Floatx.repr(Floatx.parse("1.7976931348623157e308"))], ["5e-324", "1.7976931348623157e+308"])
  t.eq("repr of infinities and NaN", [Floatx.repr(Floatx.infinity), Floatx.repr(Floatx.infinity(true)), Floatx.repr(Floatx.nan)], ["inf", "-inf", "nan"])
  t.eq("the exponent switch is at 1e16 and 1e-4 like Python", [Floatx.repr(Floatx.parse("1e15")), Floatx.repr(Floatx.parse("1e16")), Floatx.repr(Floatx.parse("0.0001")), Floatx.repr(Floatx.parse("0.00001"))], ["1000000000000000.0", "1e+16", "0.0001", "1e-05"])

  # conversions from other numbers
  t.eq("of(Int)", Floatx.repr(Floatx.of(7)), "7.0")
  t.eq("of(BigInt) rounds to nearest even", Floatx.repr(Floatx.of((1 << 70) + 1)), "1.1805916207174113e+21")
  t.eq("of(2**53+1) ties to even", Floatx.repr(Floatx.of(9007199254740993)), "9007199254740992.0")
  t.eq("of(2**53+3) ties to even", Floatx.repr(Floatx.of(9007199254740995)), "9007199254740996.0")
  t.eq("of(negative Int)", Floatx.repr(Floatx.of(0 - 12345)), "-12345.0")
  t.eq("of(Decimal)", Floatx.repr(Floatx.of(0.1)), "0.1")
  t.eq("of(Float) is the identity", Floatx.repr(Floatx.of(Floatx.parse("2.5"))), "2.5")
  t.raises("of(String) is refused", "cannot convert String") ->
    Floatx.of("1.5")

  # formatting rounds the exact binary value, half to even
  t.eq("fixed rounds 2.675 down (it is 2.67499999...)", Floatx.fixed(Floatx.parse("2.675"), 2), "2.67")
  t.eq("fixed rounds the exact tie 0.125 to even", Floatx.fixed(Floatx.parse("0.125"), 2), "0.12")
  t.eq("fixed keeps the sign of a value that rounds to zero", Floatx.fixed(Floatx.parse("-0.001"), 2), "-0.00")
  t.eq("fixed with no places", [Floatx.fixed(Floatx.parse("0.5"), 0), Floatx.fixed(Floatx.parse("1.5"), 0), Floatx.fixed(Floatx.parse("2.5"), 0)], ["0", "2", "2"])
  t.eq("fixed of an Int", Floatx.fixed(12, 3), "12.000")
  t.eq("general drops trailing zeros", [Floatx.general(Floatx.parse("100")), Floatx.general(Floatx.parse("2.5")), Floatx.general(Floatx.parse("0.00012345"))], ["100", "2.5", "0.00012345"])
  t.eq("general switches to exponent form", [Floatx.general(Floatx.parse("123456789")), Floatx.general(Floatx.parse("0.00001234"))], ["1.23457e+08", "1.234e-05"])
  t.eq("percent", [Floatx.percent(Floatx.parse("0.12345"), 1), Floatx.percent(Floatx.parse("0.5"), 0), Floatx.percent(1, 2)], ["12.3%", "50%", "100.00%"])
  t.eq("round is Python's round(x, n)", [Floatx.repr(Floatx.round(Floatx.parse("0.126"), 2)), Floatx.repr(Floatx.round(Floatx.parse("2.675"), 2)), Floatx.repr(Floatx.round(Floatx.parse("0.125"), 2))], ["0.13", "2.67", "0.12"])

  # parse: accepted spellings and refusals (Python's float())
  t.eq("parse accepts sign, whitespace, underscores, a bare fraction or exponent", [Floatx.repr(Floatx.parse(" +1_0.5e1 ")), Floatx.repr(Floatx.parse(".5")), Floatx.repr(Floatx.parse("5.")), Floatx.repr(Floatx.parse("-inf")), Floatx.repr(Floatx.parse("NaN"))], ["105.0", "0.5", "5.0", "-inf", "nan"])
  ["", "abc", "1e", "e5", "1.2.3", "0x10", "1__0", "_1", "1_", "--1"].each -> (text)
    t.raises("parse refuses '" + text + "'", "could not convert string to float") ->
      Floatx.parse(text)

  # field access
  x = Floatx.parse("-2.5")
  t.eq("fields of -2.5", Floatx.fields(x), [true, 1024, 1125899906842624])
  t.eq("magnitude of 0.5 is 2^52 * 2^-53", Floatx.magnitude(Floatx.parse("0.5")), [4503599627370496, 0 - 53])
  t.ok("nan? / infinite? / zero? / negative?", Floatx.nan?(Floatx.nan) && Floatx.infinite?(Floatx.infinity(true)) && Floatx.zero?(Floatx.zero(true)) && Floatx.negative?(Floatx.zero(true)) && !Floatx.nan?(x))

# The Textx entry points for Python's float formats (thin wrappers over Floatx).
-> gf2_textx_float_cases(t)
  x = Floatx.of(100) * Floatx.of(1000 - 917) / Floatx.of(1000)
  t.eq("100.0 * (a - b) / a in doubles, formatted like f'{rel:.4f}'", [Textx.fixed(x, 4), Textx.fixed(x, 2), Textx.fixed(x, 0)], ["8.3000", "8.30", "8"])
  t.eq("percent: f'{tol:.1%}' and f'{tol:.0%}'", [Textx.percent(Floatx.parse("0.03"), 1), Textx.percent(Floatx.parse("0.03"), 0), Textx.percent(0, 1)], ["3.0%", "3%", "0.0%"])
  t.eq("general: f'{x:g}' on integers and floats", [Textx.general(12), Textx.general(Floatx.parse("2.5")), Textx.general(1234567), Textx.general(0.0001)], ["12", "2.5", "1.23457e+06", "0.0001"])
  t.eq("parse_float: float(os.environ.get('CLOSURE_TOL', '0'))", [Floatx.repr(Textx.parse_float("0")), Floatx.repr(Textx.parse_float("0.01")), Floatx.repr(Textx.parse_float("1e-3"))], ["0.0", "0.01", "0.001"])
  t.raises("parse_float refuses text", "could not convert string to float") ->
    Textx.parse_float("three")
  t.eq("round: round(time.time() - t0, 2)", Floatx.repr(Textx.round(Floatx.parse("3.14159"), 2)), "3.14")
  t.eq("fixed of an exact tie rounds to even like Python", [Textx.fixed(Floatx.parse("0.5"), 0), Textx.fixed(Floatx.parse("1.5"), 0), Textx.fixed(Floatx.parse("2.5"), 0), Textx.fixed(Floatx.parse("0.125"), 2)], ["0", "2", "2", "0.12"])
  t.eq("ratio rounds int / int like Python", [Floatx.repr(Floatx.ratio(1, 3)), Floatx.repr(Floatx.ratio(3, 2)), Floatx.repr(Floatx.ratio(0 - 7, 2)), Floatx.repr(Floatx.ratio(1 << 80, 3))], ["0.3333333333333333", "1.5", "-3.5", "4.029752732048764e+23"])
  t.raises("ratio by zero", "division by zero") ->
    Floatx.ratio(1, 0)
