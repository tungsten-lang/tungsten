module Tungsten::AST
  class Nil < Node
    def clone
      self.class.new
    end

    def ==(other)
      other.is_a?(Nil)
    end
  end
end
