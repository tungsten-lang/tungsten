# frozen_string_literal: true

module Tungsten
  class Key
    SHIFT = 1
    ALT   = 2
    CTRL  = 4
    SUPER = 8

    MODIFIER_NAMES = {
      CTRL  => "Ctrl",
      ALT   => "Alt",
      SHIFT => "Shift",
      SUPER => "Cmd",
    }.freeze

    MODIFIER_SYMBOLS = {
      CTRL  => "\u2303",  # ⌃
      ALT   => "\u2325",  # ⌥
      SHIFT => "\u21E7",  # ⇧
      SUPER => "\u2318",  # ⌘
    }.freeze

    MODIFIER_ORDER = [CTRL, ALT, SHIFT, SUPER].freeze

    # Full-word modifier names (used in spelled-out forms: CTRL+D, ctrl+d)
    MODIFIER_LOOKUP = {
      "ctrl"  => CTRL,  "control" => CTRL,
      "alt"   => ALT,   "option"  => ALT,   "opt" => ALT, "meta" => ALT,
      "shift" => SHIFT,
      "super" => SUPER, "cmd"     => SUPER, "command" => SUPER, "win" => SUPER,
    }.freeze

    # Single-letter abbreviations (used ONLY in abbreviated form: C-d, S-enter)
    ABBREV_MODIFIER_LOOKUP = {
      "c" => CTRL,
      "a" => ALT,  "m" => ALT,
      "s" => SHIFT,
      "d" => SUPER,
    }.freeze

    # Codepoints for named keys
    CODEPOINTS = {}.tap do |h|
      ("a".."z").each { |c| h[c] = c.ord }
      ("A".."Z").each { |c| h[c] = c.ord }
      ("0".."9").each { |c| h[c] = c.ord }

      h["enter"]     = 13
      h["return"]    = 13
      h["tab"]       = 9
      h["esc"]       = 27
      h["escape"]    = 27
      h["space"]     = 32
      h["backspace"] = 127

      h["delete"]    = 57358
      h["insert"]    = 57348

      h["up"]        = 57352
      h["down"]      = 57353
      h["left"]      = 57354
      h["right"]     = 57355

      h["home"]      = 57356
      h["end"]       = 57357
      h["pageup"]    = 57358
      h["pagedown"]  = 57359

      (1..12).each { |n| h["f#{n}"] = 57363 + n }
    end.freeze

    LEGACY_SEQUENCES = {
      57352 => "\e[A",   # UP
      57353 => "\e[B",   # DOWN
      57355 => "\e[C",   # RIGHT
      57354 => "\e[D",   # LEFT
      57356 => "\e[H",   # HOME
      57357 => "\e[F",   # END
      57358 => "\e[3~",  # DELETE
      57348 => "\e[2~",  # INSERT
      57359 => "\e[5~",  # PAGEUP  (oops, swap)
    }.tap do |h|
      h[57364] = "\eOP"   # F1
      h[57365] = "\eOQ"   # F2
      h[57366] = "\eOR"   # F3
      h[57367] = "\eOS"   # F4
      h[57368] = "\e[15~" # F5
      h[57369] = "\e[17~" # F6
      h[57370] = "\e[18~" # F7
      h[57371] = "\e[19~" # F8
      h[57372] = "\e[20~" # F9
      h[57373] = "\e[21~" # F10
      h[57374] = "\e[23~" # F11
      h[57375] = "\e[24~" # F12
    end.freeze

    DISPLAY_KEYS = {
      13  => "\u21A9",  # ↩ Enter
      9   => "\u21E5",  # ⇥ Tab
      27  => "\u238B",  # ⎋ Esc
      32  => "\u2423",  # ␣ Space
      127 => "\u232B",  # ⌫ Backspace
      57358 => "\u2326", # ⌦ Delete
      57352 => "\u2191", # ↑ Up
      57353 => "\u2193", # ↓ Down
      57354 => "\u2190", # ← Left
      57355 => "\u2192", # → Right
    }.freeze

    attr_reader :base_key, :codepoint, :modifiers

    def initialize(base_key, codepoint, modifiers = 0)
      @base_key  = base_key&.freeze
      @codepoint = codepoint
      @modifiers = modifiers
      freeze
    end

    def self.parse(str)
      str = str.strip
      raise Tungsten::Error, "empty key literal" if str.empty?

      parts = str.split(" ")
      if parts.size > 1
        # Key sequence: split on spaces, parse each
        parts.map { |p| parse_single(p) }
      else
        parse_single(str)
      end
    end

    def self.parse_single(str)
      mods = 0
      base = nil

      abbreviated = str.match?(/\A[A-Z]-/)
      tokens = abbreviated ? str.split("-") : str.split(/[+-]/)

      tokens.each do |tok|
        downcased = tok.downcase
        # In abbreviated mode, only single uppercase letters are modifiers
        mod_bit = if abbreviated && tok.length == 1 && tok.match?(/\A[A-Z]\z/)
                    ABBREV_MODIFIER_LOOKUP[downcased]
                  else
                    MODIFIER_LOOKUP[downcased]
                  end

        if mod_bit
          mods |= mod_bit
        else
          raise Tungsten::Error, "cannot add two base keys" if base
          base = downcased
        end
      end

      if base
        cp = CODEPOINTS[base]
        raise Tungsten::Error, "unknown key: #{base}" unless cp
        Key.new(base, cp, mods)
      else
        # Modifier-only key
        Key.new(nil, nil, mods)
      end
    end

    def self.from_kitty(str)
      m = str.match(/\A\e\[(\d+)(?:;(\d+))?u\z/)
      raise Tungsten::Error, "invalid kitty sequence" unless m

      cp = m[1].to_i
      mod_param = m[2]&.to_i || 1
      mods = mod_param - 1

      base = CODEPOINTS.key(cp)
      Key.new(base, cp, mods)
    end

    def self.from_legacy(byte)
      byte = byte.to_i
      if byte >= 1 && byte <= 26
        letter = (byte + 96).chr
        Key.new(letter, letter.ord, CTRL)
      elsif byte >= 32 && byte <= 126
        ch = byte.chr
        Key.new(ch.downcase, ch.ord, 0)
      else
        raise Tungsten::Error, "cannot convert legacy byte #{byte} to Key"
      end
    end

    def kitty
      raise Tungsten::Error, "modifier-only key has no kitty sequence" unless @codepoint

      mod_param = @modifiers + 1
      if mod_param > 1
        "\e[#{@codepoint};#{mod_param}u"
      else
        "\e[#{@codepoint}u"
      end
    end

    def legacy
      return nil unless @codepoint

      if @modifiers == CTRL && @codepoint >= 97 && @codepoint <= 122
        # Ctrl+letter → byte 1-26
        (@codepoint - 96).chr
      elsif @modifiers == 0
        if @codepoint < 128
          @codepoint.chr
        else
          LEGACY_SEQUENCES[@codepoint]
        end
      else
        nil
      end
    end

    def bytes
      leg = legacy
      if leg
        leg.bytes
      else
        kitty.bytes
      end
    end

    def name
      parts = []
      MODIFIER_ORDER.each do |mod|
        parts << MODIFIER_NAMES[mod] if (@modifiers & mod) != 0
      end
      parts << key_display_name if @base_key
      parts.join("+")
    end

    def display
      parts = +""
      MODIFIER_ORDER.each do |mod|
        parts << MODIFIER_SYMBOLS[mod] if (@modifiers & mod) != 0
      end
      if @base_key
        sym = DISPLAY_KEYS[@codepoint]
        if sym
          parts << sym
        elsif @base_key.length == 1
          parts << @base_key.upcase
        else
          parts << @base_key.capitalize
        end
      end
      parts
    end

    def shift?  = (@modifiers & SHIFT) != 0
    def ctrl?   = (@modifiers & CTRL) != 0
    def alt?    = (@modifiers & ALT) != 0
    def super?  = (@modifiers & SUPER) != 0

    def printable?
      return false unless @codepoint
      return false if @modifiers != 0

      (@codepoint >= 33 && @codepoint <= 126) || (@codepoint >= 65 && @codepoint <= 90)
    end

    def functional?
      return false unless @codepoint

      @codepoint >= 57352
    end

    def modifier?
      @base_key.nil?
    end

    def to_s
      if printable?
        @codepoint.chr
      else
        name
      end
    end

    def inspect
      "#[#{canonical_form}]"
    end

    def ==(other)
      other.is_a?(Key) && @codepoint == other.codepoint && @modifiers == other.modifiers
    end
    alias eql? ==

    def hash
      [@codepoint, @modifiers].hash
    end

    def +(other)
      raise Tungsten::Error, "can only add Key to Key" unless other.is_a?(Key)
      raise Tungsten::Error, "cannot add two base keys" if @base_key && other.base_key

      if other.base_key
        Key.new(other.base_key, other.codepoint, @modifiers | other.modifiers)
      else
        Key.new(@base_key, @codepoint, @modifiers | other.modifiers)
      end
    end

    def -(other)
      raise Tungsten::Error, "can only subtract Key from Key" unless other.is_a?(Key)
      raise Tungsten::Error, "can only subtract modifier keys" if other.base_key

      Key.new(@base_key, @codepoint, @modifiers & ~other.modifiers)
    end

    private

    def key_display_name
      if @base_key.length == 1
        @base_key.upcase
      else
        @base_key.split("_").map(&:capitalize).join
      end
    end

    def canonical_form
      parts = []
      MODIFIER_ORDER.each do |mod|
        parts << MODIFIER_NAMES[mod].upcase if (@modifiers & mod) != 0
      end
      parts << key_display_name if @base_key
      parts.join("+")
    end
  end
end
