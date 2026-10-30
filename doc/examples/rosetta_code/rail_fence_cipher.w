# Rail fence cipher

-> rail_encrypt(text, rails)
  chars = text.chars
  rows = []
  r = 0
  while r < rails
    rows.push("")
    r += 1
  rail = 0
  dir = 1
  i = 0
  while i < chars.size
    rows[rail] += chars[i]
    if rail == 0
      dir = 1
    elsif rail == rails - 1
      dir = -1
    rail += dir
    i += 1
  rows.join("")

<< rail_encrypt("WEAREDISCOVEREDFLEEATONCE", 3)
<< rail_encrypt("ROSETTACODE", 4)

## expect stdout
## WECRLTEERDSOEEFEAOCAIVDEN
## RAOTCSTOEED
