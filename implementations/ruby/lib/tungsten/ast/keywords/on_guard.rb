module Tungsten::AST
  # Compile-time platform guard block.
  #
  #   on macos
  #     -> clock_ms()
  #       ...
  #
  #   on linux && x86_64 with io_uring
  #     -> submit(...)
  #       ...
  #
  # The predicate is a target expression tree (TargetAnd/Or/Not/Designator).
  # Capabilities are the trailing `with` clause feature names.
  # Body contains the definitions that are only active when the guard matches.
  #
  class OnGuard < Node
    attr_accessor :predicate, :capabilities, :body

    def initialize(predicate, capabilities, body = nil)
      @predicate = predicate
      @capabilities = capabilities
      @body = List.from(body)
    end

    def ==(other)
      super && other.predicate    == predicate &&
               other.capabilities == capabilities &&
               other.body         == body
    end

    def clone
      self.class.new(predicate.clone, capabilities.dup, body.clone).tap do |n|
        n.location = location
      end
    end

    def to_sexp
      [:on_guard, @predicate.to_sexp, @capabilities, @body.to_sexp]
    end
  end
end
