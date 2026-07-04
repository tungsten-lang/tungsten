module Tungsten::AST
  class Int < Value
    def initialize(value)
      @value =
        case value
        when Integer
          value
        when String
          parse_literal(value)
        else
          value.to_i
        end
    end

    private

    def parse_literal(raw)
      text = raw.delete("_")
      sign = 1

      if text.start_with?("-")
        sign = -1
        text = text[1..]
      elsif text.start_with?("+")
        text = text[1..]
      end

      prefix = text[0, 2]&.downcase
      base, digits =
        case prefix
        when "0b" then [2, text[2..]]
        when "0o" then [8, text[2..]]
        when "0d" then [10, text[2..]]
        when "0x" then [16, text[2..]]
        else [10, text]
        end

      sign * digits.to_i(base)
    end
  end
end
