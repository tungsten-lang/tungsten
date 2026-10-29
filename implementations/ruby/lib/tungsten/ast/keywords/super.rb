module Tungsten::AST
  class Super < Node
    attr_accessor :args

    def initialize(args = [])
      @args = args || []
    end

    def eval_in(interp)
      interp.visit_super(self)
    end

    def ==(other)
      super && other.args == args
    end
  end
end
