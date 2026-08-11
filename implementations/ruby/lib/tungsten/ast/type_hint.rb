module Tungsten::AST
  # Postfix machine-type coercion (`value ## i64`). Assignment hints use the
  # same conversion through AST::Assign; this node covers casts on arbitrary
  # expressions and native data-field reads.
  class TypeHint < Node
    attr_accessor :value, :hint

    def initialize(value, hint)
      @value = value
      @hint = hint
    end

    def children
      yield @value if @value.is_a?(Node)
    end

    def clone
      self.class.new(@value.clone, @hint).tap { |node| node.location = location }
    end
  end
end
