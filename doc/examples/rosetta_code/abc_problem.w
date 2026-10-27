# ABC problem

-> can_make_word?(word, blocks)
  chars = word.upcase.chars
  used = []
  i = 0
  while i < blocks.size
    used.push(false)
    i += 1

  -> backtrack(idx, chars, blocks, used)
    if idx == chars.size
      return true
    ch = chars[idx]
    b = 0
    while b < blocks.size
      if !used[b] && blocks[b].include?(ch)
        used[b] = true
        if backtrack(idx + 1, chars, blocks, used)
          return true
        used[b] = false
      b += 1
    false

  backtrack(0, chars, blocks, used)

blocks = ["BO", "XK", "DQ", "CP", "NA", "GT", "RE", "TG", "QD", "FS", "JW", "HU", "VI", "AN", "OB", "ER", "FS", "LY", "PC", "ZM"]
words = ["A", "BARK", "BOOK", "TREAT", "COMMON", "SQUAD", "CONFUSE"]
words.each -> (w)
  << "[w]: [can_make_word?(w, blocks)]"

## expect stdout
## A: true
## BARK: true
## BOOK: false
## TREAT: true
## COMMON: false
## SQUAD: true
## CONFUSE: true
