module Tungsten::AST
  class Is < Node
    attr_accessor :trait_name

    def initialize(trait_name)
      @trait_name = Tungsten::AST.intern_name(trait_name)
    end

    def ==(other)
      super && other.trait_name == trait_name
    end
  end
end
