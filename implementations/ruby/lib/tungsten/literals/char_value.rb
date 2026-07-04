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
      ByteArray.new(to_s.bytes)
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
      [ self ]
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

    def noncharacter?
      @codepoint.between?(0xFDD0, 0xFDEF) || (@codepoint & 0xFFFE) == 0xFFFE
    end

    def category
      GENERAL_CATEGORIES.each_key do |code|
        return code if unicode_property?(code)
      end
      nil
    end

    def general_category
      GENERAL_CATEGORIES[category]
    end

    def unicode_name
      nil
    end

    def name
      unicode_name || unicode_escape
    end

    def letter?
      unicode_property?("L")
    end
    alias alphabetic? letter?
    alias alpha? letter?

    def mark?
      unicode_property?("M")
    end

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

    def uppercase?
      unicode_property?("Lu")
    end
    alias upper? uppercase?

    def titlecase?
      unicode_property?("Lt")
    end

    def whitespace?
      to_s.match?(/\A[[:space:]]\z/)
    end
    alias space? whitespace?

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
    alias xdigit? hex_digit?

    def id_start?
      unicode_property?("XID_Start")
    end

    def id_continue?
      unicode_property?("XID_Continue")
    end

    def upcase
      mapped_char(to_s.upcase)
    end
    alias uppercase upcase

    def downcase
      mapped_char(to_s.downcase)
    end
    alias lowercase downcase

    def titlecase
      mapped_char(to_s.capitalize)
    end

    def casefold
      mapped_char(to_s.downcase)
    end

    def swapcase
      mapped_char(to_s.swapcase)
    end

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
