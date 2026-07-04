# Balanced brackets

-> balanced?(s)
  depth = 0
  i = 0
  while i < s.length
    if s[i] == "["
      depth += 1
    elsif s[i] == "]"
      depth -= 1
      if depth < 0
        return false
    i += 1
  depth == 0

tests = ["", "[]", "[][]", "[[][]]", "][", "][][", "[]][[]"]
tests.each { |t|
  if balanced?(t)
    puts "\"[t]\" is balanced"
  else
    puts "\"[t]\" is NOT balanced"
}

## expect skip currently unsupported in this runtime
