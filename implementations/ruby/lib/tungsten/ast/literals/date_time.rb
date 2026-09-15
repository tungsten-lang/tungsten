module Tungsten::AST
  class DateTime < Value
    def initialize(value)
      # Keep the source spelling. Ruby's DateTime cannot store second 60
      # (it clamps or raises), so Tungsten::DateTime validates leap seconds
      # from the text the same way Date.parse does.
      @value = value.to_s
    end
  end
end
