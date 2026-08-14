# Literal-regex captures are dynamically sized; indices above nine must not be
# truncated by the lexer or native runtime. A failed match clears prior TLS
# captures on the same thread.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

captures = if /(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)/ =~ "abcdefghijk" then [$1, $9, $10, $11]
check("regex.capture.dynamic", captures, ["a", "i", "j", "k"])

cleared = if /(x)/ =~ "no match" then $1 else $1
check("regex.capture.failed_match_clears", cleared, nil)

# Regex literals expose the same structured result shape as Core Regex. This
# numbered-group fixture runs on both Oniguruma and the POSIX fallback; named
# literal groups are covered by the Oniguruma runtime contract.
match_data = /(é)(猫)?()/.match_data("xé")
check("regex.match_data.type", match_data.class_name, "RegexMatch")
check("regex.match_data.whole", match_data[0], "é")
check("regex.match_data.group", match_data[1], "é")
check("regex.match_data.unmatched", match_data[2], nil)
check("regex.match_data.empty", match_data[3], "")
check("regex.match_data.offset", match_data.offset(1), [1, 2])
check("regex.match_data.unmatched_offset", match_data.offset(2), nil)
check("regex.match_data.empty_offset", match_data.offset(3), [2, 2])
check("regex.match_data.begin", match_data.begin_offset(), 1)
check("regex.match_data.end", match_data.end_offset(), 2)
check("regex.match_data.match", match_data.match(), "é")
check("regex.match_data.size", match_data.size(), 4)
check("regex.match_data.captures", match_data.captures(), ["é", nil, ""])
check("regex.match_data.names", match_data.names(), [])
check("regex.match_data.named_captures", match_data.named_captures(), {})
check("regex.match_data.named_offsets", match_data.named_offsets(), {})
check("regex.match_data.to_a", match_data.to_a(), ["é", "é", nil, ""])
check("regex.match_data.to_s", match_data.to_s(), "é")
check("regex.match_data.unknown_name", match_data["missing"], nil)
check("regex.match_data.unknown_symbol", match_data[:missing], nil)

<< "regex capture storage: all green"
