module Tungsten::AST
  class WValue < Value
    attr_reader :raw

    def initialize(value)
      @value =
        case value
        when String
          value.delete_prefix("u0x").to_i(16)
        else
          value.to_i
        end

      @raw = format("u0x%016X", @value)
    end
  end
end
