# Palindrome detection

-> palindrome?(s)
  s == s.reverse

words = ["racecar", "hello", "madam", "world", "level", "noon"]
words.each -> (w)
  if palindrome?(w)
    << "[w] is a palindrome"
  else
    << "[w] is not a palindrome"

## expect stdout
## racecar is a palindrome
## hello is not a palindrome
## madam is a palindrome
## world is not a palindrome
## level is a palindrome
## noon is a palindrome
