-> check(name, value)
  raise "FAIL [name]" if !value
  << "PASS [name]"
pattern = Regex.new("^\[a-z]\[a-z0-9_-]{0,63}$")
check("ordinary branch spill", pattern.match?("fixture"))
check("ordinary branch spill rejects suffix", !pattern.match?("fixture!"))
check("repeated matching", pattern.match?("another-name"))
check("bound enforced", !pattern.match?("a" * 65))

check("greedy count", Regex.new("a{1,3}").match_data("aaaa")[0] == "aaa")
check("lazy count", Regex.new("a{1,3}?").match_data("aaaa")[0] == "a")
check("bounded capture", Regex.new("^(a){1,3}b$").match_data("aaab")[1] == "a")
check("bounded alternation", Regex.new("^(?:a|ab){1,3}c$").match?("ababc"))

check("line anchor searches later lines", Regex.new("^checks: (\\d+) failures=(0)$").match?("prefix 𓀀\nchecks: 191 failures=0\n"))
check("absolute anchor stays absolute", !Regex.new("\\Achecks:").match?("prefix\nchecks: 191\n"))
check("dot does not cross newline by default", !Regex.new("^a.b$").match?("a\nb"))
