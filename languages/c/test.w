# Test the C lexer — tokenize a C file and verify token count

use lexer

args = argv()
if args.size() == 0
  << "usage: test.w <file.c>"
  exit(1)

file = args[0]

source = read_file(file)
lc = source.lchs()
count = lc.size()

<< "Tokenizing: [file] ([count] chars)"

tokens = i64[count]
n = c_tokenize(lc, count, tokens)

<< "Tokens: [n]"
<< "OK"
