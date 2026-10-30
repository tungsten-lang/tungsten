module Tungsten::AST
  class Symbol < Value
    def initialize(value)
      @value = Tungsten::AST.intern_name_without_prefix(value, ":")
      @runtime_symbol = @value.to_sym
    end

    def eval_in(_interp)
      @runtime_symbol
    end
  end
end
