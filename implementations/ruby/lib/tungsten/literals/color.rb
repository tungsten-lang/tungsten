# frozen_string_literal: true

module Tungsten
  class Color < Literal
    def self.rgb(r, g, b) = new(r.to_i, g.to_i, b.to_i)
    def self.from(arr) = new(arr[0].to_i, arr[1].to_i, arr[2].to_i)
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

    # ANSI true-color rendering for REPL display
    def ansi_swatch(text = "  ")
      lum = 0.299 * @r + 0.587 * @g + 0.114 * @b
      fg = lum > 128 ? "38;2;0;0;0" : "38;2;255;255;255"
      "\e[48;2;#{@r};#{@g};#{@b}m\e[#{fg}m#{text}\e[0m"
    end
  end
end
