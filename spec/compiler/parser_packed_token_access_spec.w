# Parser-hot packed-token access and equality must decode values after Array
# storage and retrieval. Untagged packed values fit in Integer; the signed
# W_TAG_CHAR form exceeds i48 and materializes as BigInt, matching the real
# lexer/parser path. Equality deliberately extracts length and offset from one
# normalized raw value; the high-bit checks guard that shared conversion. The
# public accessor checks also cover their top-level direct-helper wrappers.

use ../../compiler/lib/parser

-> check(name, got, want)
  if got != want
    << "FAIL packed token " + name + " got=" + got.to_s() + " want=" + want.to_s()
    exit(1)
  << "PASS packed token " + name

-> after_array(value)
  values = [value]
  values[0]

+ PackedTokenParserProbe < Parser
  -> new

tag = -1125899906842624
type_scale = 274877906944
length_scale = 67108864

type_id = 255
offset = 16777215
length = 4095
high_bits = tag + type_id * type_scale + length * length_scale + offset * 4
high_token = after_array(high_bits)

small_type = 7
small_offset = 1
small_length = 3
small_bits = small_type * type_scale + small_length * length_scale + small_offset * 4
small_token = after_array(small_bits)

# Keep the equality fields small while retaining the real token tag/high type
# bits, so tok_equal? exercises its single BigInt-to-i64 normalization before
# decoding both length and offset.
equal_high_bits = tag + type_id * type_scale + small_length * length_scale + small_offset * 4
equal_high_token = after_array(equal_high_bits)

tokens = [high_token, small_token, equal_high_token]
# The accessors do not read parser state. Override the constructor so the tree
# interpreter test does not require Parser#new's unrelated native location
# table registry.
parser = PackedTokenParserProbe.new()

check("high-bit type", parser.tok_type(tokens[0]), type_id)
check("high-bit offset", parser.tok_off(tokens[0]), offset)
check("high-bit length", parser.tok_len(tokens[0]), length)
check("small type", parser.tok_type(tokens[1]), small_type)
check("small offset", parser.tok_off(tokens[1]), small_offset)
check("small length", parser.tok_len(tokens[1]), small_length)

parser.set_chars(["x", "a", "b", "c", "y"])
check("small equality", parser.tok_equal?(tokens[1], "ignored", "abc"), true)
check("small inequality", parser.tok_equal?(tokens[1], "ignored", "abd"), false)
check("small length mismatch", parser.tok_equal?(tokens[1], "ignored", "ab"), false)
check("high-bit equality", parser.tok_equal?(tokens[2], "ignored", "abc"), true)
check("high-bit inequality", parser.tok_equal?(tokens[2], "ignored", "abd"), false)
check("high-bit length mismatch", parser.tok_equal?(tokens[2], "ignored", "ab"), false)

<< "PASS parser packed token access"
