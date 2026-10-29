module Tungsten::AST
  class CaseExpr < Node
    attr_accessor :receiver, :whens, :else_body, :literal_case_lookup

    def initialize(receiver, whens, else_body = nil)
      @receiver = receiver
      @whens = whens
      @else_body = List.from(else_body)
      @literal_case_lookup = nil
    end

    def eval_in(interp)
      interp.visit_case_expr(self)
    end

    def ==(other)
      super && other.receiver == receiver &&
               other.whens == whens &&
               other.else_body == else_body
    end

    def children
      yield @receiver if @receiver.is_a?(Node)
      @whens.each do |conditions, body|
        conditions.each { |condition| yield condition if condition.is_a?(Node) }
        yield body if body.is_a?(Node)
      end
      yield @else_body if @else_body.is_a?(Node)
    end
  end
end
