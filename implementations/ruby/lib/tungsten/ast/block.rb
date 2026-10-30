module Tungsten::AST
  class Block < Node
    attr_accessor :args, :body, :free_var_cache, :slot_names_template,
                  :simple_block_plan, :free_var_slot_names_template, :has_next_flag

    def initialize(args = [], body = nil)
      @args = args
      @body = List.from body
      @free_var_cache = nil
      @slot_names_template = nil
      @simple_block_plan = nil
      @free_var_slot_names_template = nil
      @has_next_flag = -1
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
