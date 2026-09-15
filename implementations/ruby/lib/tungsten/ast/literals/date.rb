module Tungsten::AST
  class Date < Value
    def initialize(value)
      # Keep the source spelling. Catch-up days (Sweden 1712-02-30, Julian
      # century leaps) are not Gregorian, so ::Date.parse would reject them
      # at parse time; Tungsten::Date validates on evaluation.
      @value = value.to_s
    end
  end
end
