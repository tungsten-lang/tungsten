module Tungsten::AST
  class Use < Node
    attr_accessor :path

    def initialize(path)
      @path = path
    end

    def eval_in(interp)
      interp.visit_use(self)
    end

    def ==(other)
      super && other.path == path
    end
  end
end
