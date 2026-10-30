# Word frequency

text = "to be or not to be that is the question whether tis nobler in the mind to suffer the slings and arrows"
words = text.split(" ")
counts = {}
unique = []

words.each -> (w)
  if counts[w] == nil
    counts[w] = 0
    unique.push(w)
  counts[w] += 1

# Sort unique words by descending frequency
n = unique.size
i = 1
while i < n
  key = unique[i]
  j = i - 1
  while j >= 0 && counts[unique[j]] < counts[key]
    unique[j + 1] = unique[j]
    j -= 1
  unique[j + 1] = key
  i += 1

(0...5).each -> (k)
  w = unique[k]
  << "[w]: [counts[w]]"

## expect stdout
## to: 3
## the: 3
## be: 2
## or: 1
## not: 1
