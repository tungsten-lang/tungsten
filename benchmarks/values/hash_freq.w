t0 = clock

num_words = 1000
num_iter = 5000000

words = []
wi = 0
while wi < num_words
  words.push("word" + wi.to_s())
  wi = wi + 1

freq = {}
seed = 42

j = 0
while j < num_iter
  seed = (((seed * 1103515245) & 0xFFFFFFFF) + 12345) & 0x7FFFFFFF
  word = words[seed % num_words]
  if freq[word] == nil
    freq[word] = 0
  freq[word] = freq[word] + 1
  j = j + 1

max_freq = 0
keys = freq.keys()

k = 0
while k < keys.size()
  v = freq[keys[k]]
  if v > max_freq
    max_freq = v
  k = k + 1

t1 = clock
<< max_freq
<< "elapsed: [t1 - t0]s"
