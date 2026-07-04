require "bigdecimal"
require "bigdecimal/util"

class ::Array
  def array
    Tungsten::AST::ArrayLiteral.new self
  end
end

class FalseClass
  def boolean
    Tungsten::AST::Boolean.new self
  end
end

class TrueClass
  def boolean
    Tungsten::AST::Boolean.new self
  end
end

class BigDecimal
  def decimal
    Tungsten::AST::Decimal.new self
  end
end

class Integer
  def int
    Tungsten::AST::Int.new self
  end

  def float
    Tungsten::AST::Float.new self.to_f
  end

  def decimal
    Tungsten::AST::Decimal.new self
  end
end

class Fixnum
  def int
    Tungsten::AST::Int.new self
  end

  def float
    Tungsten::AST::Float.new self.to_f
  end

  def decimal
    Tungsten::AST::Decimal.new self
  end
end

class Float
  def float
    Tungsten::AST::Float.new self
  end

  def decimal
    Tungsten::AST::Decimal.new self
  end
end

class String
  def call(*args)
    Tungsten::AST::Call.new nil, self, args
  end

  def var
    Tungsten::AST::Var.new self
  end

  def str
    Tungsten::AST::StringLiteral.new self
  end

  def symbol
    Tungsten::AST::Symbol.new self
  end

  def ivar
    Tungsten::AST::InstanceVar.new self
  end
end

class Symbol
  def symbol
    Tungsten::AST::Symbol.new self.to_s
  end
end

class NilClass
  def nil_node
    Tungsten::AST::Nil.new
  end
end

module QuantityHelper
  def self.quantity(number_node, unit_string)
    Tungsten::AST::QuantityLiteral.new(number_node, unit_string)
  end
end

module ByteArrayHelper
  def self.byte_array(*bytes)
    Tungsten::AST::ByteArrayLiteral.new(bytes)
  end
end
