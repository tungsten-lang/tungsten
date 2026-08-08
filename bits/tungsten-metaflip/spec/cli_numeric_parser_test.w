use ../lib/metaflip/cli

failures = 0 ## i64

-> cli_expect_parse(label, text, expected_ok, expected_value) (String String i64 i64) i64
  output = i64[1]
  output[0] = 717
  actual_ok = ffcli_parse_i64(text, output) ## i64
  if actual_ok != expected_ok
    << "FAIL " + label + " accepted=" + actual_ok.to_s() + " expected=" + expected_ok.to_s()
    return 1
  if expected_ok == 1 && output[0] != expected_value
    << "FAIL " + label + " value=" + output[0].to_s() + " expected=" + expected_value.to_s()
    return 1
  0

-> cli_expect_value(label, actual, expected) (String i64 i64) i64
  if actual != expected
    << "FAIL " + label + " value=" + actual.to_s() + " expected=" + expected.to_s()
    return 1
  0

failures += cli_expect_parse("zero", "0", 1, 0)
failures += cli_expect_parse("positive sign", "+42", 1, 42)
failures += cli_expect_parse("negative", "-42", 1, 0 - 42)
failures += cli_expect_parse("leading zeroes", "00017", 1, 17)
failures += cli_expect_parse("i64 maximum", "9223372036854775807", 1, 9223372036854775807)
failures += cli_expect_parse("i64 minimum", "-9223372036854775808", 1, 0 - 9223372036854775807 - 1)

failures += cli_expect_parse("empty", "", 0, 0)
failures += cli_expect_parse("sign only", "-", 0, 0)
failures += cli_expect_parse("leading space", " 12", 0, 0)
failures += cli_expect_parse("trailing junk", "12threads", 0, 0)
failures += cli_expect_parse("decimal point", "1.0", 0, 0)
failures += cli_expect_parse("i64 positive overflow", "9223372036854775808", 0, 0)
failures += cli_expect_parse("i64 negative overflow", "-9223372036854775809", 0, 0)

failures += cli_expect_value("square tensor", ffcli_parse_square_tensor("05X05"), 5)
failures += cli_expect_value("tensor prefix junk", ffcli_parse_square_tensor("5junkx5junk"), 0)
failures += cli_expect_value("tensor trailing separator", ffcli_parse_square_tensor("5x5x"), 0)
failures += cli_expect_value("tensor overflow", ffcli_parse_square_tensor("9223372036854775808x9223372036854775808"), 0)
failures += cli_expect_value("scaled integer", ffcli_parse_scaled_moves("500M"), 500000000)
failures += cli_expect_value("scaled fraction", ffcli_parse_scaled_moves("1.25b"), 1250000000)
failures += cli_expect_value("scaled trailing junk", ffcli_parse_scaled_moves("12oops"), 0 - 1)
failures += cli_expect_value("scaled trailing decimal", ffcli_parse_scaled_moves("12."), 0 - 1)
failures += cli_expect_value("scaled leading decimal", ffcli_parse_scaled_moves(".5m"), 0 - 1)
failures += cli_expect_value("scaled overflow", ffcli_parse_scaled_moves("9223372036854775807k"), 0 - 1)

portfolio = i64[4]
failures += cli_expect_value("valid move portfolio", ffcli_parse_move_portfolio("25M,125M,625M,2.5B", portfolio), 1)
failures += cli_expect_value("portfolio first value", portfolio[0], 25000000)
failures += cli_expect_value("portfolio last value", portfolio[3], 2500000000)
failures += cli_expect_value("invalid move portfolio", ffcli_parse_move_portfolio("25M,125M,nope,2.5B", portfolio), 0)

if failures != 0
  exit(1)

<< "PASS strict Metaflip CLI numeric parser"
