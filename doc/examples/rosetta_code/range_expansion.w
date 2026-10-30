# Range expansion

-> expand_range_token(tok)
  chars = tok.chars
  # Find the '-' separating start and end (ignoring a leading '-')
  dash_pos = -1
  i = 1
  while i < chars.size
    if chars[i] == "-"
      dash_pos = i
      break
    i += 1
  if dash_pos == -1
    return [tok.to_i]
  lo = tok.slice(0, dash_pos).to_i
  hi = tok.slice(dash_pos + 1, chars.size - dash_pos - 1).to_i
  out = []
  v = lo
  while v <= hi
    out.push(v)
    v += 1
  out

-> range_expand(spec)
  tokens = spec.split(",")
  result = []
  i = 0
  while i < tokens.size
    vals = expand_range_token(tokens[i])
    j = 0
    while j < vals.size
      result.push(vals[j])
      j += 1
    i += 1
  result

<< range_expand("-6,-3--1,3-5,7-11,14,15,17-20")

## expect stdout
## [-6, -3, -2, -1, 3, 4, 5, 7, 8, 9, 10, 11, 14, 15, 17, 18, 19, 20]
