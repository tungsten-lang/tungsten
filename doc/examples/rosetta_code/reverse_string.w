# Reverse a string

-> reverse(s)
  chars = s.chars
  out = ""
  i = chars.size - 1
  while i >= 0
    out += chars[i]
    i -= 1
  out

<< reverse("Hello, World!")
<< reverse("asdf")
<< reverse("racecar")

## expect stdout
## !dlroW ,olleH
## fdsa
## racecar
