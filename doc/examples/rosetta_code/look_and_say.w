# Look-and-say sequence

-> look_and_say(s)
  result = ""
  i = 0
  while i < s.length
    c = s[i]
    count = 1
    while i + count < s.length and s[i + count] == c
      count += 1
    result += count.to_s + c
    i += count
  result

s = "1"
1.upto(10) { |_|
  puts s
  s = look_and_say(s)
}

## expect skip currently unsupported in this runtime
