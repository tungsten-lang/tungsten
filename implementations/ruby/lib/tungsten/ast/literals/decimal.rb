require "bigdecimal"
require "bigdecimal/util"

module Tungsten::AST
  class Decimal < Value
    def initialize(value)
      cleaned = value.to_s.gsub(/[$K_]/, "").delete("\u2212")
      cleaned = "-#{cleaned}" if value.to_s.start_with?("\u2212")
      @value = cleaned.to_d
    end
  end
end
