module Tungsten::AST
  class CurrencyLiteral < Node
    attr_accessor :value_str, :symbol

    def initialize(value_str, symbol)
      @value_str = value_str
      @symbol = symbol
    end

    def ==(other)
      other.is_a?(CurrencyLiteral) &&
        other.value_str == @value_str &&
        other.symbol == @symbol
    end

    def children; end
  end
end
