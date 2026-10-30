# Vigenere cipher

-> vigenere(text, key, decrypt)
  tc = text.upcase.chars
  kc = key.upcase.chars
  out = ""
  ki = 0
  i = 0
  while i < tc.size
    c = tc[i]
    code = c.ord
    if code >= 65 && code <= 90
      shift = kc[ki % kc.size].ord - 65
      if decrypt
        shift = (26 - shift) % 26
      out += (((code - 65 + shift) % 26) + 65).chr
      ki += 1
    i += 1
  out

plain = "Beware the Jabberwock, my son! The jaws that bite, the claws that catch!"
key = "VIGENERECIPHER"
enc = vigenere(plain, key, false)
dec = vigenere(enc, key, true)
<< enc
<< dec

## expect stdout
## WMCEEIKLGRPIFVMEUGXQPWQVIOIAVEYXUEKFKBTALVXTGAFXYEVKPAGY
## BEWARETHEJABBERWOCKMYSONTHEJAWSTHATBITETHECLAWSTHATCATCH
