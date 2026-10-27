# Burrows-Wheeler transform

-> sort_strings(arr)
  n = arr.size
  i = 1
  while i < n
    key = arr[i]
    j = i - 1
    while j >= 0 && arr[j] > key
      arr[j + 1] = arr[j]
      j -= 1
    arr[j + 1] = key
    i += 1
  arr

-> bwt_encode(s)
  text = "^" + s + "|"
  chars = text.chars
  n = chars.size
  table = []
  i = 0
  while i < n
    rot = ""
    j = 0
    while j < n
      rot += chars[(i + j) % n]
      j += 1
    table.push(rot)
    i += 1
  table = sort_strings(table)
  out = ""
  i = 0
  while i < n
    row_chars = table[i].chars
    out += row_chars[n - 1]
    i += 1
  out

-> bwt_decode(r)
  chars = r.chars
  n = chars.size
  table = []
  i = 0
  while i < n
    table.push("")
    i += 1
  step = 0
  while step < n
    i = 0
    while i < n
      table[i] = chars[i] + table[i]
      i += 1
    table = sort_strings(table)
    step += 1
  i = 0
  while i < n
    row = table[i]
    if row.starts_with?("^") && row.ends_with?("|")
      return row.slice(1, n - 2)
    i += 1
  ""

encoded = bwt_encode("BANANA")
<< encoded
<< bwt_decode(encoded)

## expect stdout
## BNN^AA|A
## BANANA
