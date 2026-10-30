# Caesar cipher

-> caesar_encrypt(text, shift)
  result = ""
  chars = text.chars
  i = 0
  while i < chars.size
    c = chars[i]
    code = c.ord
    if code >= 97 && code <= 122
      result += (((code - 97 + shift) % 26) + 97).chr
    elsif code >= 65 && code <= 90
      result += (((code - 65 + shift) % 26) + 65).chr
    else
      result += c
    i += 1
  result

-> caesar_decrypt(text, shift)
  caesar_encrypt(text, 26 - shift)

plain = "The quick brown fox jumps over the lazy dog"
encrypted = caesar_encrypt(plain, 13)
decrypted = caesar_decrypt(encrypted, 13)

<< "Plain:     [plain]"
<< "Encrypted: [encrypted]"
<< "Decrypted: [decrypted]"

## expect stdout
## Plain:     The quick brown fox jumps over the lazy dog
## Encrypted: Gur dhvpx oebja sbk whzcf bire gur ynml qbt
## Decrypted: The quick brown fox jumps over the lazy dog
