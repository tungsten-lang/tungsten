# ROT13 cipher

-> rot13(s)
  result = ""
  i = 0
  while i < s.length
    c = s[i]
    if c >= "a" and c <= "z"
      result += (((c.ord - 97 + 13) % 26) + 97).chr
    elsif c >= "A" and c <= "Z"
      result += (((c.ord - 65 + 13) % 26) + 65).chr
    else
      result += c
    i += 1
  result

puts rot13("Hello, World!")
puts rot13("Uryyb, Jbeyq!")

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten rot13.w`
## expect stdout
## Uryyb, Jbeyq!
## Hello, World!
