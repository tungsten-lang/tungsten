s = "hello"

<< "[s] template"          # => hello template
<< s                       # => hello

<< s + " literal"          # => hello literal
<< s                       # => hello

s += " literal"
<< s                       # => hello literal

s << " appended"
<< s                       # => hello literal appended

s = "hello"
<< s.concat(" literal")    # => hello literal
<< s                       # => hello literal

<< s.prepend("She said: ") # => She said: hello literal
<< s                       # => She said: hello literal

## expect stdout
## hello template
## hello
## hello literal
## hello
## hello literal
## hello literal appended
## hello literal
## hello literal
## She said: hello literal
## She said: hello literal
