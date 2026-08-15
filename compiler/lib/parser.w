# Recursive descent parser for tungsten
use ast
use ../../core/token

# Parser-internal packed-token decoders are top-level functions so hot parser
# sites lower to direct calls instead of one-argument method inline caches.
# The public Parser methods below remain as compatibility wrappers.
-> parser_tok_type(p)
  bits = ccall_nobox("w_numeric_to_i64", p)
  (bits >> 38) & 0xFF

-> parser_tok_off(p)
  bits = ccall_nobox("w_numeric_to_i64", p)
  (bits >> 2) & 0xFFFFFF

-> parser_tok_len(p)
  bits = ccall_nobox("w_numeric_to_i64", p)
  (bits >> 26) & 0xFFF

use parser/core
use parser/expressions
use parser/definitions
