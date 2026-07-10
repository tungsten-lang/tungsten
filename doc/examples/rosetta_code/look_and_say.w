# Look-and-say sequence

-> look_and_say(s)
  result = ""
  i = 0
  while i < s.size
    c = s[i]
    count = 1
    while i + count < s.size and s[i + count] == c
      count += 1
    result += count.to_s + c
    i += count
  result

s = "1"
(1..10).each -> (_)
  << s
  s = look_and_say(s)

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten look_and_say.w`
## expect stdout
## 1
## 11
## 21
## 1211
## 111221
## 312211
## 13112221
## 1113213211
## 31131211131221
## 13211311123113112211
