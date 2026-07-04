module Tungsten::AST
  # 'while' condition
  #    expressions
  #
  class While < Node
    attr_accessor :condition, :body, :check_first

    def initialize(condition, body = nil, check_first)
      @condition = condition
      @body = List.from body
      @check_first = check_first
    end

    def children
      yield @condition if @condition.is_a?(Node)
      yield @body if @body.is_a?(Node)
    end

    def ==(other)
      super && other.condition == condition &&
               other.body      == body
    end

    def clone
      self.class.new(condition.clone, body.clone, check_first).tap do |node|
        node.location = location
      end
    end

    def sexp_name
      :while
    end

    def to_sexp
      [sexp_name, @condition.to_sexp, @body.to_sexp, @check_first]
    end
  end

  class Until < While
    def sexp_name
      :until
    end
  end
end
