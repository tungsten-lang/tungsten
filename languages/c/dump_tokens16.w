use ./lexer16

SRC = "int add(int a, int b) {\n  // sum\n  return a + b;\n}\n#include <x>\n#define M 1\nchar c='a';float f=3.14e-2;\nfloat h=0x1.fp3; float d=.5; pp=1e+;\na->b == c && d != e || f++ + g-- - h*i / j%k ^ l|m & n<<2 >>1\nx /* outer /* not nested */ y\n// trailing\nu8\"a\\nb\" \\u0041 <% %> a#b\nint x; // hellö wörld\n"

## i64: i, v, ty, ln, off, tc, mask_ln, mask_off
## i64[]: tokens
fn hot_dump(tokens, tc)
  mask_ln = 16383
  mask_off = 16777215
  i = 0
  while i < tc
    v = tokens[i]
    ty = (v >> 38) & 15
    ln = (v >> 24) & mask_ln
    off = v & mask_off
    << "[i]:[ty]:[ln]:[off]"
    i += 1

lc = SRC.lchs("c", bits: 16)
n = lc.size()
tokens = i64[n + 16]
tc = c_tokenize_fast16(lc, n, tokens)
hot_dump(tokens, tc)
