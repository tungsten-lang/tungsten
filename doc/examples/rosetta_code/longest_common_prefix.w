# Longest common prefix

-> lcp(strings)
  if strings.empty?
    return ""
  first = strings[0].chars
  min_len = first.size
  i = 1
  while i < strings.size
    sz = strings[i].size
    if sz < min_len
      min_len = sz
    i += 1
  prefix = ""
  pos = 0
  while pos < min_len
    ch = first[pos]
    k = 1
    while k < strings.size
      if strings[k].slice(pos, 1) != ch
        return prefix
      k += 1
    prefix += ch
    pos += 1
  prefix

<< lcp(["interspecies", "interstellar", "interstate"])
<< lcp(["throne", "throne"])
<< lcp(["throne", "dungeon"])
<< lcp(["prefix", "suffix"])

## expect stdout
## inters
## throne
## 
## 
