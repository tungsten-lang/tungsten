module Tungsten::AST
  class QuantityLiteral < Node
    attr_accessor :number, :unit_string

    def initialize(number, unit_string)
      @number = number
      @unit_string = unit_string
    end

    def ==(other)
      other.is_a?(QuantityLiteral) &&
        other.number == @number &&
        other.unit_string == @unit_string
    end

    def children
      yield @number if @number.is_a?(Node)
    end
  end
end
