# Comma quibbling

-> quibble(words)
  n = words.size
  if n == 0
    return "{}"
  if n == 1
    return "{[words[0]]}"
  prefix = []
  i = 0
  while i < n - 1
    prefix.push(words[i])
    i += 1
  joined = prefix.join(", ")
  "{[joined] and [words[n - 1]]}"

<< quibble([])
<< quibble(["ABC"])
<< quibble(["ABC", "DEF"])
<< quibble(["ABC", "DEF", "G", "H"])

## expect stdout
## {}
## {ABC}
## {ABC and DEF}
## {ABC, DEF, G and H}
