# Block parameters captured only in one branch must be initialized on every call.
+ ConditionalCapture
  -> .scan(text, flags)
    values = []
    active = true
    text.split(",").each ->(line)
      if active
        flags.each ->(flag)
          active = line == "never"
      values.push(line)
    values

<< ConditionalCapture.scan("selected,next,last", [1]).join(",")

+ LexicalLookup:Sibling
  -> .value
    42

+ LexicalLookup:Parent
  -> .sibling
    Sibling.value

+ LexicalChild < LexicalLookup:Parent

<< LexicalChild.sibling
