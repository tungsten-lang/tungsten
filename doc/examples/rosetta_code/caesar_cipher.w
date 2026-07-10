# Caesar cipher

-> caesar_encrypt(text, shift)
  result = ""
  i = 0
  while i < text.size
    c = text[i]
    if c >= "a" and c <= "z"
      result += (((c.ord - 97 + shift) % 26) + 97).chr
    elsif c >= "A" and c <= "Z"
      result += (((c.ord - 65 + shift) % 26) + 65).chr
    else
      result += c
    i += 1
  result

-> caesar_decrypt(text, shift)
  caesar_encrypt(text, 26 - shift)

plain = "The quick brown fox jumps over the lazy dog"
encrypted = caesar_encrypt(plain, 13)
decrypted = caesar_decrypt(encrypted, 13)

puts "Plain:     [plain]"
puts "Encrypted: [encrypted]"
puts "Decrypted: [decrypted]"

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten caesar_cipher.w`
## expect stdout
## Plain:     The quick brown fox jumps over the lazy dog
## Encrypted: Gur dhvpx oebja sbk whzcf bire gur ynml qbt
## Decrypted: The quick brown fox jumps over the lazy dog
