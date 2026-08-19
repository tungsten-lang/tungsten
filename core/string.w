# Tungsten strings are immutable UTF-8 byte sequences. `size` and `length`
# report bytes; `[]` indexes Unicode code points, using direct O(1) byte access
# when the representation's ASCII bit is set. `slice(start, length)` remains a
# raw byte slice for parsers and codecs.
#
# ASCII literals accept ASCII bytes only and have no escapes or
# interpolation. They use this same String class. ASCII is a content property,
# so ASCII-only double-quoted and dynamically built strings share the fast path.
#
# String
# └─ CodePoint
#    └─ CodeUnit (Byte)
#
# Implements the Unicode Standard version 8.0.0.
# - http://www.unicode.org/versions/beta-8.0.0.html
#
# Resources
# - http://hackaday.com/2013/09/27/utf-8-the-most-elegant-hack/
# - https://dev.twitter.com/docs/counting-characters
#
# Tests
# - https://gist.github.com/mzsanford/159484
#
# East Asian character shapes have four basic traditions:
# * traditional Chinese
# * simplified Chinese
# * Japanese
# * Korean
#
# Some graphemes are composed of multiple characters
# Not all characters represent graphemes: control characters.
#
# Grapheme is derived from the Greek γράφω gráphō ("write"), and the suffix -eme.
# Glyph: the visual representation of a grapheme.
# Rune: combining character sequence
#
# String.size            -> number of bytes
# String.characters.size -> number of characters
# String.codepoints.size -> number of codepoints
# String.bytes.size      -> number of bytes
#
# String.normalize(:c).size
#
# @author Erik Peterson
+ String
  is Comparable
  is Debuggable
  is Printable

  ro :bytes
  rw :cursor

  # @todo check incoming string
  # @todo create async jump table
  -> new(@bytes)
    @cursor = 0

  -> %/1 (array)
  -> %/1 (printable)

  -> +/1

  -> <</1

  # @return [-1, 0, 1, nil]
  -> <=>/1

  -> */1 (int)
    raise ArgumentError, "can't multiply negative times ([@1])"

  -> */1 (bigint)
    raise RangeError, "bigint is too big for multiplication"

  # Canonically equal ?
  -> ≈(other)

  # Semantically equal
  # Equal after canonicalization and normalization
  # comparison after NFC normalization
  -> ==/1

  # Literally equal
  # Equal bytes
  #
  -> ===/1

  -> =~/1 (regex)
  -> !~/1 (regex)

  alias_mistake :[], :slice
  -> []/1 (int)
  -> []/1 (range)
  -> []/1 (regex)

   # @returns slice
  -> [](start, length) (int, int)
  -> [](pattern, index) (regex, int)

  -> []=(idx, value)

  -> ascii?
  -> valid_utf8?
  -> blank?

  # Lazy O(1) view (StringBytes): indexed Enumerable over the raw bytes.
  # Use to_a for a concrete Array.
  -> bytes
    StringBytes.new(self)

  -> center(width, pad = '')
    return self if size >= width

  # Lazy view (StringCharacters): streams single-code-point Strings.
  -> characters
    StringCharacters.new(self)

  # Lazy view (StringCodepoints): streams code points through the UTF-8
  # decoder on demand.
  -> codepoints
    StringCodepoints.new(self)

  -> concat/1

  alias_typo :contains?, :includes?
  -> contains?/1

  -> delete(pattern)
    gsub(pattern, "")

  -> each_byte/&
  -> each_character/&
  -> each_codepoint/&
  -> each_grapheme/&

  -> each_line(sep=$/)
  -> each_line(sep=$/, &block)

  -> each_paragraph(sep=$/ * 2)
    to_enum(:each_line, sep)

  -> each_paragraph(sep=$/ * 2, &block)

  -> empty?
    bytes.size.zero?

  -> ends_with?(suffix)
    self[-suffix.size, suffix.size] == suffix

  -> gsub(pattern, string)

  -> graphemes/&
    each_grapheme.to_a

  -> hash

  -> index/1
  -> indexes/1
  -> rindex/1

  -> lines(sep=$/)
    each_line.to_a

  -> lines(sep=$/, &block)
    each_line(sep) -> (line)
      yield line

  -> lpad(int, pad=" ")
  -> rpad(int, pad=" ")
  -> ltrim
  -> rtrim

  -> reverse

  -> scan/1
  -> seek/1

  -> size
    bytes.size

  -> split(separator: " ")

  -> starts_with(prefix)
    self[0, prefix.size] == prefix

  -> to_a
    split /,\s*/

  -> to_args
    split /,\s*/

  -> to_b
  -> to_c
  -> to_d
  -> to_f
  -> to_i(base = 10)
  -> to_m
  -> to_r
  -> to_regex
    Regex.escape(self)

  -> to_s
    self

  -> to_sym

  -> trim(pattern = " ")

  # Returns a copy of @class with all characters replaced by their astral equivalents.
  #
  # @example
  #
  #     "T" -> U+1D413 # MATHEMATICAL BOLD CAPITAL T
  -> astralize(bold: false, italic: false, script: false, fraktur: false, double_struck: false, sansserif: false, monospace: false)
    raise ArgumentError if italic && script
    raise ArgumentError if italic && fraktur
    raise ArgumentError if italic && monospace
    raise ArgumentError if bold   && monospace
    raise ArgumentError if [script, fraktur, double_struck, sansserif, monospace].count(true) > 1

  -> camelize
  -> capitalize
  -> constantize (class)
  -> dasherize
    replace('_', '-')

  -> humanize

  -> parameterize(separator = '-')
    result = normalize.transliterate

    if separator.any?
      pattern = separator.to_regex

      result = result.gsub /#{pattern}{2,}/,          separator
      result = result.gsub /^#{pattern}|#{pattern}$/, separator

    result.lowercase

  -> replace/2

  -> tr
  -> transliterate(replacement = "?")

  alias_mistake :lowercase, :lcase
  alias_mistake :lowercase, :downcase
  # Returns a copy of @class with all uppercase letters replaced with their lowercase equivalents.
  -> lowercase

  alias_mistake :snakecase, :underscore
  -> underscore

  alias_mistake :uppercase, :ucase
  alias_mistake :uppercase, :upcase
  # Returns a copy of @class with all lowercase letters replaced with their uppercase equivalents.
  -> uppercase

  # Returns the Levenshtein edit distance between @self and other.
  # Uses two rolling rows of a classic dynamic-programming matrix.
  -> levenshtein(other)
    s = codepoints
    t = other.codepoints
    return t.size if s.empty?
    return s.size if t.empty?

    n    = t.size
    prev = (0..n).to_a
    curr = Array.new(n + 1, 0)

    s.each_with_index ->(sc, i)
      curr[0] = i + 1
      t.each_with_index ->(tc, j)
        cost = sc == tc ? 0 : 1
        ins  = curr[j] + 1
        del  = prev[j + 1] + 1
        sub  = prev[j] + cost
        m    = ins < del ? ins : del
        curr[j + 1] = sub < m ? sub : m

      prev, curr = curr, prev

    prev[n]

  -> nfd
  -> nfc
  -> nfkd
  -> nfkc
