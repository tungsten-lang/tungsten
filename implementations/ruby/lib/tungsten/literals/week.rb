# frozen_string_literal: true

module Tungsten
  class Week < Literal
    def initialize(value)
      super(value.to_s.freeze)
    end
  end
end
