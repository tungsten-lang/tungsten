# frozen_string_literal: true

module Tungsten
  class Color < Literal
    def self.rgb(r, g, b) = new(r.to_i & 0xFF, g.to_i & 0xFF, b.to_i & 0xFF)
    def self.rgba(r, g, b, a) = new(r.to_i & 0xFF, g.to_i & 0xFF, b.to_i & 0xFF, a.to_i & 0xFF)
    def self.from(arr)
      arr.size >= 4 ? rgba(arr[0], arr[1], arr[2], arr[3]) : rgb(arr[0], arr[1], arr[2])
    end
    def self.hex(str)
      s = str.to_s
      s = s[1..] if s.start_with?("#")
      raise RuntimeError, "invalid hex color digit" unless s.match?(/\A[0-9a-fA-F]+\z/)
      case s.bytesize
      when 3
        rgb(s[0].to_i(16) * 17, s[1].to_i(16) * 17, s[2].to_i(16) * 17)
      when 4
        rgba(s[0].to_i(16) * 17, s[1].to_i(16) * 17, s[2].to_i(16) * 17, s[3].to_i(16) * 17)
      when 6
        rgb(s[0, 2].to_i(16), s[2, 2].to_i(16), s[4, 2].to_i(16))
      when 8
        rgba(s[0, 2].to_i(16), s[2, 2].to_i(16), s[4, 2].to_i(16), s[6, 2].to_i(16))
      else
        raise RuntimeError, "invalid hex color length"
      end
    end
    def self.hue_rgb(h) = from(hue_to_rgb(h.to_i))
    def self.desat(rgb, pct)
      rgb = rgb.is_a?(Color) ? [rgb.r, rgb.g, rgb.b] : rgb
      from(rgb.map { |c| c + (128 - c) * (100 - pct.to_i) / 100 })
    end
    def self.darken(rgb, pct)
      rgb = rgb.is_a?(Color) ? [rgb.r, rgb.g, rgb.b] : rgb
      from(rgb.map { |c| c * pct.to_i / 100 })
    end

    def self.hue_to_rgb(h)
      h %= 360
      s, f = h / 60, (h % 60) * 255 / 60
      case s
      when 0 then [255, f, 0]
      when 1 then [255 - f, 255, 0]
      when 2 then [0, 255, f]
      when 3 then [0, 255 - f, 255]
      when 4 then [f, 0, 255]
      else        [255, 0, 255 - f]
      end
    end

    attr_reader :r, :g, :b, :a

    def initialize(r, g, b, a = 255)
      @r = r
      @g = g
      @b = b
      @a = a
      @value = [r, g, b, a]
    end

    def to_s
      @a == 255 ? format("#%02X%02X%02X", @r, @g, @b) : format("#%02X%02X%02X%02X", @r, @g, @b, @a)
    end

    def inspect = to_s

    def to_rgba_u32
      ((@a & 0xFF) << 24) | ((@b & 0xFF) << 16) | ((@g & 0xFF) << 8) | (@r & 0xFF)
    end

    def to_bgra_u32
      ((@a & 0xFF) << 24) | ((@r & 0xFF) << 16) | ((@g & 0xFF) << 8) | (@b & 0xFF)
    end

    # ANSI true-color rendering for REPL display
    def ansi_swatch(text = "  ")
      lum = 0.299 * @r + 0.587 * @g + 0.114 * @b
      fg = lum > 128 ? "38;2;0;0;0" : "38;2;255;255;255"
      "\e[48;2;#{@r};#{@g};#{@b}m\e[#{fg}m#{text}\e[0m"
    end
  end
end
