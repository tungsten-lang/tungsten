module Tungsten::AST
  class Symbol < Value
    def initialize(value)
      @value = Tungsten::AST.intern_name_without_prefix(value, ":")
    end

    def eval_in(interp)
      interp.cached_symbol_value(self)
    end
  end
end
