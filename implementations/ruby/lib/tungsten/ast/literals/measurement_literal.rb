module Tungsten::AST
  # `5.0 ± 0.1` or `2.1232442(2)` — a scalar with Gaussian uncertainty.
  # The number node is whatever the lexer matched (Int, Float, Decimal);
  # the uncertainty is stored as a Float computed at parse time.
  class MeasurementLiteral < Node
    attr_accessor :number, :uncertainty

    def initialize(number, uncertainty)
      @number = number
      @uncertainty = uncertainty
    end

    def ==(other)
      other.is_a?(MeasurementLiteral) &&
        other.number == @number &&
        other.uncertainty == @uncertainty
    end

    def children
      yield @number if @number.is_a?(Node)
    end
  end
end
