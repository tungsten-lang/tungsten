# Native String methods that are safe to express over the WValue itself.
#
# The legacy core/string.w file remains the long-form API/design scaffold.
# Keep this file deliberately small and parseable so primitive String values
# can register their 0xF9 type-class dispatch without loading that scaffold.

+ String
  # String modes 0..5 store their byte count directly in bits 1..3. Modes 6
  # and 7 are slab/heap strings and are only constructed for non-empty data;
  # rope receivers are flattened before String type-class dispatch. Therefore
  # mode 0 is exactly the canonical empty string (and empty symbol) encoding.
  -> empty?
    (($value >> 1) & 7) == 0
