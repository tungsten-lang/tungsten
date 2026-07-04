# Palindrome detection

-> palindrome?(s)
  s == s.reverse

words = ["racecar", "hello", "madam", "world", "level", "noon"]
words.each { |w|
  if palindrome?(w)
    puts "[w] is a palindrome"
  else
    puts "[w] is not a palindrome"
}

## expect skip currently unsupported in this runtime
