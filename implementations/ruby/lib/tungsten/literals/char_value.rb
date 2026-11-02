# frozen_string_literal: true

module Tungsten
  class CharValue
    include Comparable

    GENERAL_CATEGORIES = {
      "Lu" => "Uppercase Letter",
      "Ll" => "Lowercase Letter",
      "Lt" => "Titlecase Letter",
      "Lm" => "Modifier Letter",
      "Lo" => "Other Letter",
      "Mn" => "Nonspacing Mark",
      "Mc" => "Spacing Mark",
      "Me" => "Enclosing Mark",
      "Nd" => "Decimal Number",
      "Nl" => "Letter Number",
      "No" => "Other Number",
      "Pc" => "Connector Punctuation",
      "Pd" => "Dash Punctuation",
      "Ps" => "Open Punctuation",
      "Pe" => "Close Punctuation",
      "Pi" => "Initial Quote Punctuation",
      "Pf" => "Final Quote Punctuation",
      "Po" => "Other Punctuation",
      "Sm" => "Math Symbol",
      "Sc" => "Currency Symbol",
      "Sk" => "Modifier Symbol",
      "So" => "Other Symbol",
      "Zs" => "Space Separator",
      "Zl" => "Line Separator",
      "Zp" => "Paragraph Separator",
      "Cc" => "Control",
      "Cf" => "Format",
      "Cs" => "Surrogate",
      "Co" => "Private Use",
      "Cn" => "Unassigned"
    }.freeze

    SCRIPT_NAMES = %w[
      Common Inherited Latin Greek Cyrillic Armenian Hebrew Arabic
      Syriac Thaana Devanagari Bengali Gurmukhi Gujarati Oriya Tamil
      Telugu Kannada Malayalam Sinhala Thai Lao Tibetan Myanmar
      Georgian Hangul Ethiopic Cherokee Canadian_Aboriginal Ogham Runic Khmer
      Mongolian Hiragana Katakana Bopomofo Han Yi Old_Italic Gothic
      Deseret Tagalog Hanunoo Buhid Tagbanwa Limbu Tai_Le Linear_B
      Ugaritic Shavian Osmanya Cypriot Braille Buginese Coptic New_Tai_Lue
      Glagolitic Tifinagh Syloti_Nagri Old_Persian Kharoshthi Balinese Cuneiform Phoenician
      Phags_Pa Nko Sundanese Lepcha Ol_Chiki Vai Saurashtra Kayah_Li
      Rejang Lycian Carian Lydian Cham Tai_Tham Tai_Viet Avestan
      Egyptian_Hieroglyphs Samaritan Lisu Bamum Javanese Meetei_Mayek Imperial_Aramaic Old_South_Arabian
      Inscriptional_Parthian Inscriptional_Pahlavi Old_Turkic Kaithi Batak Brahmi Mandaic Chakma
      Meroitic_Cursive Meroitic_Hieroglyphs Miao Sharada Sora_Sompeng Takri
    ].freeze

    attr_reader :codepoint

    def initialize(value)
      @codepoint =
        case value
        when CharValue then value.codepoint
        when Integer then value
        when String
          raise RangeError, "empty character" if value.empty?

          value.codepoints.first
        else
          value.to_i
        end
      validate_codepoint!(@codepoint)
    end

    def self.valid_codepoint?(codepoint)
      codepoint.is_a?(Integer) && codepoint.between?(0, 0x10FFFF) && !surrogate?(codepoint)
    end

    def self.surrogate?(codepoint)
      codepoint.between?(0xD800, 0xDFFF)
    end

    def self.shift_codepoint(codepoint, delta)
      shifted = codepoint + delta
      shifted += delta while surrogate?(shifted)
      validate_codepoint!(shifted)
      shifted
    end

    def self.validate_codepoint!(codepoint)
      return if valid_codepoint?(codepoint)

      raise RangeError, "invalid Unicode scalar value U+#{codepoint.to_i.to_s(16).upcase}"
    end

    def <=>(other)
      other_codepoint =
        case other
        when CharValue then other.codepoint
        when Integer then other
        when String then other.codepoints.first
        end
      return nil unless other_codepoint

      @codepoint <=> other_codepoint
    end

    def ==(other)
      (self <=> other)&.zero? || false
    end
    alias eql? ==

    def coerce(other)
      return [other, @codepoint] if other.is_a?(Integer)

      raise TypeError, "#{self.class} can't be coerced into #{other.class}"
    end

    def hash
      @codepoint.hash
    end

    def +(offset)
      self.class.new(self.class.shift_codepoint(@codepoint, offset.to_i))
    end

    def -(other)
      return @codepoint - other.codepoint if other.is_a?(CharValue)

      self.class.new(self.class.shift_codepoint(@codepoint, -other.to_i))
    end

    def succ
      self + 1
    end
    define_method(:next) { succ }

    def pred
      self - 1
    end
    alias prev pred

    def ord
      @codepoint
    end
    alias to_i ord

    def chr
      to_s
    end

    def to_s(_base = nil)
      [ @codepoint ].pack("U")
    end

    def inspect
      unicode_escape
    end

    def bytes
      to_s.bytes
    end

    def byte_size
      to_s.bytesize
    end

    def length
      1
    end
    alias size length

    def empty?
      false
    end

    def chars
      [ to_s ]
    end

    def codepoints
      [ @codepoint ]
    end

    def unicode_escape
      "U+#{@codepoint.to_s(16).upcase.rjust(@codepoint <= 0xFFFF ? 4 : 6, "0")}"
    end
    alias uplus unicode_escape

    def hex
      @codepoint.to_s(16).upcase
    end

    def ascii?
      @codepoint < 0x80
    end

    def latin1?
      @codepoint < 0x100
    end

    def bmp?
      @codepoint <= 0xFFFF
    end

    def astral?
      @codepoint > 0xFFFF
    end

    def valid?
      self.class.valid_codepoint?(@codepoint)
    end
    alias scalar? valid?

    def to_codepoint
      self
    end

    def to_char
      raise Tungsten::Error, "invalid ASCII character U+#{@codepoint.to_s(16).upcase}" unless ascii?

      self
    end

    def noncharacter?
      @codepoint.between?(0xFDD0, 0xFDEF) || (@codepoint & 0xFFFE) == 0xFFFE
    end
    alias noncharacter_code_point noncharacter?
    alias nchar noncharacter?

    def category
      GENERAL_CATEGORIES.each_key do |code|
        return code if unicode_property?(code)
      end
      nil
    end

    def general_category
      GENERAL_CATEGORIES[category]
    end
    alias gc general_category

    def block
      return "ASCII" if @codepoint < 128
      return "Latin-1 Supplement" if @codepoint < 256
      return "BMP" if @codepoint <= 0xFFFF

      "Supplementary"
    end
    alias blk block

    def script
      SCRIPT_NAMES.each do |name|
        return name if unicode_property?(name)
      end
      "Common"
    end
    alias sc script

    def unicode_name
      nil
    end
    alias na unicode_name

    def unicode_1_name
      nil
    end
    alias na1 unicode_1_name

    def name
      unicode_name || unicode_escape
    end

    def combining_class
      mark? ? 230 : 0
    end
    alias ccc combining_class

    def grapheme_base
      !mark? && !control?
    end
    alias gr_base grapheme_base

    def grapheme_extend
      mark?
    end
    alias gr_ext grapheme_extend

    def letter?
      unicode_property?("L")
    end
    alias alphabetic? letter?
    alias alphabetic letter?
    alias alpha? letter?
    alias alpha letter?

    def mark?
      unicode_property?("M")
    end
    alias diacritic mark?
    alias dia mark?

    def number?
      unicode_property?("N")
    end

    def digit?
      unicode_property?("Nd")
    end

    def alnum?
      letter? || digit?
    end

    def lowercase?
      unicode_property?("Ll")
    end
    alias lower? lowercase?
    alias lower lowercase?

    def uppercase?
      unicode_property?("Lu")
    end
    alias upper? uppercase?
    alias upper uppercase?

    def titlecase?
      unicode_property?("Lt")
    end

    def whitespace?
      to_s.match?(/\A[[:space:]]\z/)
    end
    alias space? whitespace?
    alias white_space whitespace?
    alias wspace whitespace?

    def control?
      unicode_property?("Cc")
    end

    def printable?
      !control?
    end

    def punctuation?
      unicode_property?("P")
    end
    alias punct? punctuation?

    def symbol?
      unicode_property?("S")
    end

    def separator?
      unicode_property?("Z")
    end

    def hex_digit?
      ascii? && to_s.match?(/\A[0-9A-Fa-f]\z/)
    end
    alias hex_digit hex_digit?
    alias ascii_hex_digit hex_digit?
    alias ahex hex_digit?
    alias xdigit? hex_digit?

    def id_start?
      @codepoint == 95 || unicode_property?("XID_Start")
    end
    alias id_start id_start?
    alias ids id_start?
    alias xid_start id_start?
    alias xids id_start?

    def id_continue?
      unicode_property?("XID_Continue")
    end
    alias id_continue id_continue?
    alias idc id_continue?
    alias xid_continue id_continue?
    alias xidc id_continue?

    alias is_alnum? alnum?
    alias is_alpha? alpha?
    alias is_ascii? ascii?
    alias is_cntrl? control?
    alias is_digit? digit?
    def is_graph?
      !space? && !control?
    end
    alias is_lower? lower?
    alias is_number? number?
    alias is_print? printable?
    alias is_punct? punct?
    alias is_space? space?
    alias is_upper? upper?
    alias is_valid? valid?
    alias is_xdigit? xdigit?

    def upcase
      mapped_char(to_s.upcase)
    end
    alias uppercase upcase
    alias simple_uppercase_mapping upcase
    alias suc upcase
    alias uppercase_mapping upcase
    alias uc upcase

    def downcase
      mapped_char(to_s.downcase)
    end
    alias lowercase downcase
    alias simple_lowercase_mapping downcase
    alias slc downcase
    alias lowercase_mapping downcase
    alias lc downcase

    def titlecase
      return self.class.new(@codepoint - 1) if [ 454, 457, 460, 499 ].include?(@codepoint)
      return self.class.new(@codepoint + 1) if [ 452, 455, 458, 497 ].include?(@codepoint)

      mapped_char(to_s.capitalize)
    end
    alias simple_titlecase_mapping titlecase
    alias stc titlecase
    alias titlecase_mapping titlecase
    alias tc titlecase

    def casefold
      mapped_char(to_s.downcase(:fold))
    end
    alias simple_case_folding casefold
    alias scf casefold
    alias case_folding casefold
    alias cf casefold

    def swapcase
      mapped_char(to_s.swapcase)
    end

    def changes_when_lowercased
      downcase != self
    end
    alias cwl changes_when_lowercased

    def changes_when_uppercased
      upcase != self
    end
    alias cwu changes_when_uppercased

    def changes_when_titlecased
      titlecase != self
    end
    alias cwt changes_when_titlecased

    def changes_when_casefolded
      casefold != self
    end
    alias cwcf changes_when_casefolded

    def changes_when_casemapped
      changes_when_lowercased || changes_when_uppercased || changes_when_titlecased
    end
    alias cwcm changes_when_casemapped

    private

    def mapped_char(text)
      codepoints = text.codepoints
      codepoints.length == 1 ? self.class.new(codepoints.first) : text
    end

    def unicode_property?(property)
      to_s.match?(Regexp.new("\\A\\p{#{property}}\\z"))
    rescue RegexpError
      false
    end

    def validate_codepoint!(codepoint)
      self.class.validate_codepoint!(codepoint)
    end
  end
end
