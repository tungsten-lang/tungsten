# Anagrams

-> sort_chars(word)
  chars = word.chars
  n = chars.size
  i = 1
  while i < n
    key = chars[i]
    j = i - 1
    while j >= 0 && chars[j] > key
      chars[j + 1] = chars[j]
      j -= 1
    chars[j + 1] = key
    i += 1
  chars.join("")

words = ["abel", "able", "bale", "bela", "elba", "alger", "glare", "lager", "large", "regal", "evil", "levi", "live", "veil", "vile"]
groups = {}
keys = []

words.each -> (w)
  sig = sort_chars(w)
  if groups[sig] == nil
    groups[sig] = []
    keys.push(sig)
  groups[sig].push(w)

keys.each -> (k)
  << groups[k].join(", ")

## expect stdout
## abel, able, bale, bela, elba
## alger, glare, lager, large, regal
## evil, levi, live, veil, vile
