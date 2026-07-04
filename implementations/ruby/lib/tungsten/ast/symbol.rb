module Tungsten::AST
  class Symbol < Value
    def initialize(value)
      @value = Tungsten::AST.intern_name_without_prefix(value, ":")
    end
  end
end
