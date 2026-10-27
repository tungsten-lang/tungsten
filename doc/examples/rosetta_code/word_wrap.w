# Word wrap

-> word_wrap(text, width)
  words = text.split(" ")
  lines = []
  current = words[0]
  i = 1
  while i < words.size
    w = words[i]
    if current.size + 1 + w.size <= width
      current += " " + w
    else
      lines.push(current)
      current = w
    i += 1
  lines.push(current)
  lines

paragraph = "In olden times when wishing still helped one, there lived a king whose daughters were all beautiful, but the youngest was so beautiful that the sun itself, which has seen so much, was astonished whenever it shone in her face."

wrapped = word_wrap(paragraph, 45)
wrapped.each -> (line)
  << line

## expect stdout
## In olden times when wishing still helped one,
## there lived a king whose daughters were all
## beautiful, but the youngest was so beautiful
## that the sun itself, which has seen so much,
## was astonished whenever it shone in her face.
