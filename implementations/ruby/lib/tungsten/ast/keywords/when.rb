module Tungsten::AST
  class When < Node
    attr_accessor :conditions, :body, :single, :splat

    def initialize(conditions, body)
      @body = body || Nil.new
      @splat = nil
      @single = nil

      case conditions
      when ArrayLiteral
        if conditions.body.last.kind_of? When
          last = conditions.body.pop

          if last.conditions.kind_of? ArrayLiteral
            conditions.body.concat last.conditions.body
          elsif last.single
            @splat = SplatWhen.new last.single
          else
            @splat = SplatWhen.new last.conditions
          end
        end

        if conditions.body.size == 1 and !@splat
          @single = conditions.body.first
        else
          @conditions = conditions
        end
      when SplatValue, ConcatArgs, PushArgs
        @splat = SplatWhen.new conditions
        @conditions = nil
      else
        @conditions = conditions
      end
    end

    def children
      yield @body if @body.is_a?(Node)
      yield @splat if @splat.is_a?(Node)
      yield @single if @single.is_a?(Node)
      yield @conditions if @conditions.is_a?(Node)
    end

    def to_sexp
      if @single
        conditions_sexp = [:array, @single.to_sexp]
      else
        conditions_sexp = @conditions ? @conditions.to_sexp : []
        conditions_sexp << @splat.to_sexp if @splat
      end

      [:when, conditions_sexp, @body.to_sexp]
    end
  end

  class SplatWhen < Node
    attr_accessor :condition

    def initialize(condition)
      @condition = condition
    end

    def children
      yield @condition if @condition.is_a?(Node)
    end

    def to_sexp
      [:when, @condition.to_sexp, nil]
    end
  end
end
