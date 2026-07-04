s  = "Hello wo"
s += "rld"     # new string object
s << "!"       # mutates in place, same object

<< s

## expect stdout
## Hello world!
