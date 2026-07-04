module Tungsten::AST
  class GlobalVar < Node
    attr_accessor :name

    def initialize(name)
      @name = Tungsten::AST.intern_name(name)
    end

    def can_assign?
      true
    end

    def ==(other)
      super && other.name == name
    end
  end
end
