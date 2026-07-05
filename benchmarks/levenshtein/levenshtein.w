s = "the quick brown fox jumps over the lazy dog" * 20
t = "the slow brown fox leaps over the lazy cat" * 20
<< s.levenshtein(t)
