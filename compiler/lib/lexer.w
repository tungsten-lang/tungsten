# Default packed Tungsten lexer: 64-bit LexChar input, packed token output.
#
# This is the fast token stream used by the compiler lexer rewrite. It avoids
# token hashes and value string copies: tokens are packed as:
#
#   (type_id << 38) | (length << 26) | (offset << 2) | line_start_flag
#
# These are raw numeric descriptors in an i64[] scratch buffer, not boxed
# Token WValues. Token.make adds W_TAG_CHAR when a first-class Token is needed;
# the compiler lexer keeps the descriptors tagless so they remain inline Ints
# after materialization into @packed_tokens.
#
# The 12-bit length field wraps mod 4096 (`& 0xFFF` at every pack site):
# an unmasked length would OR its high bits into the type-id field and
# reclassify long tokens (a 20001-digit int became TYPE_HINT, a 79001-digit
# int became CODEPOINT). Materializers for value-carrying kinds (numbers,
# decimals, strings, heredocs, arrays) re-scan from `offset`, so the wrapped
# length is advisory — it only feeds `raw` prefix dispatch.
#
# Type ids use bits 38..45 (8 bits → 256 distinct types). The single
# preserved flag at bit 0 marks "first non-whitespace token on its source
# line"; the older sp_before / sp_after flags were dropped because the
# scanner now emits explicit :SP tokens between non-whitespace tokens,
# so the parser detects whitespace by token presence rather than a flag.
#
# The scanner expects source.lchs("tungsten"), whose flag table mirrors
# compiler/lib/lexer.w identifier semantics while adding newline dispatch.

#
# Lex64 is primarily scalar. Strict ASCII literals use a bounded, unrolled
# NEON quote scan on arm64; the narrower Lex16/Lex32 scanners still cover more
# source characters per vector for the other bulk-scan paths.

use ../../languages/tungsten/lexers/regex_helpers
use ../../languages/tungsten/lexers/known_units

use lexer/fast64
use lexer/literals
use lexer/strings
use lexer/materialize
