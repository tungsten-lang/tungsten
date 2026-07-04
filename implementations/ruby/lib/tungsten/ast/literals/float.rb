module Tungsten::AST
  class Float < Value
    def initialize(value)
      @value = value.to_s.gsub(/^~/, '').to_f
    end
  end
end
