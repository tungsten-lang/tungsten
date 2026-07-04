# Pangram checker

-> pangram?(s)
  letters = "abcdefghijklmnopqrstuvwxyz"
  lower = s.downcase
  i = 0
  while i < letters.length
    unless lower.include?(letters[i])
      return false
    i += 1
  true

tests = [
  "The quick brown fox jumps over the lazy dog"
  "The quick brown fox jumped over the lazy dog"
]
tests.each { |t|
  puts "\"[t]\": [pangram?(t)]"
}

## expect skip currently unsupported in this runtime
