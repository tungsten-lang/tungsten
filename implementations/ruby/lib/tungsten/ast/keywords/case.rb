module Tungsten::AST
  class Case < Node
    attr_accessor :whens, :else

    def initialize(whens, else_body)
      @whens = whens
      @else = else_body || Nil.new
    end

    def receiver_sexp
      nil
    end

    def to_sexp
      else_sexp = @else.kind_of?(Nil) ? nil : @else.to_sexp
      sexp = [:case, receiver_sexp]
      sexp += @whens.map { |x| x.to_sexp }
      sexp << else_sexp
      sexp
    end
  end

  class CaseWithReceiver < Node
    attr_accessor :receiver

    def initialize(receiver, whens, else_body)
      @receiver = receiver
      @whens = whens
      @else_body = else_body || Nil.new
    end

    def receiver_sexp
      @receiver.to_sexp
    end
  end
end
