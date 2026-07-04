# frozen_string_literal: true

require "date"

module Tungsten
  class Month < Literal
    def initialize(value)
      super(value.to_s.freeze)
    end

    def days
      d = ::Date.parse("#{@value}-01")
      last = ::Date.new(d.year, d.month, -1)
      Date.new(d)..Date.new(last)
    end
  end
end
