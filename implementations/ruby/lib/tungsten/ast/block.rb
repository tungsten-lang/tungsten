module Tungsten::AST
  class Block < Node
    attr_accessor :args, :body, :free_var_cache

    def initialize(args = [], body = nil)
      @args = args
      @body = List.from body
    end

    def children
      @args.each { |arg| yield arg if arg.is_a?(Node) }
      yield @body if @body.is_a?(Node)
    end

    def ==(other)
      super && other.args == args &&
               other.body == body
    end

    def clone
      self.class.new(args.map(&:clone), body.clone).tap do |node|
        node.location = location
      end
    end
  end
end
