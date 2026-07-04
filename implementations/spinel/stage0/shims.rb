# frozen_string_literal: true

# Keep stage0 compatibility shims here. This file is intentionally small until
# Spinel tells us exactly which CRuby conveniences the stage0 path still needs.

class Set
  def initialize
    @values = []
  end

  def add(value)
    value = value.to_s
    @values.push(value) unless include?(value)
    self
  end

  def delete(value)
    value = value.to_s
    i = 0
    while i < @values.length
      if @values[i] == value
        @values.delete_at(i)
        return self
      end
      i += 1
    end
    self
  end

  def include?(value)
    value = value.to_s
    i = 0
    while i < @values.length
      return true if @values[i] == value
      i += 1
    end
    false
  end

  def each(&block)
    self
  end
end

class ErrorReporter
  def initialize(color: false)
  end

  def format(error, source: nil, file: nil)
    error.to_s
  end
end

class Literal
  def initialize(value)
  end
end

class ByteArray < Literal
end

class Color < Literal
end

class Currency < Literal
  attr_reader :symbol

  def initialize(value, symbol = nil)
    @symbol = symbol
  end
end

class Percentage < Literal
end

class Quantity < Literal
end

class Duration < Literal
end

class Key < Literal
  def self.parse(value)
    new(value)
  end
end

class StringBuffer < Literal
end

class PathValue < Literal
end

class Time < Literal
end

class Builtins
  def self.setup(interpreter)
  end
end
