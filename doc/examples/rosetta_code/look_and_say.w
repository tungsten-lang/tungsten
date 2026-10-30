# Look-and-say sequence

-> look_and_say(s)
  result = ""
  chars = s.chars
  i = 0
  while i < chars.size
    c = chars[i]
    count = 1
    while i + count < chars.size && chars[i + count] == c
      count += 1
    result += count.to_s + c
    i += count
  result

s = "1"
(1..10).each -> (_)
  << s
  s = look_and_say(s)

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
