# frozen_string_literal: true

require "bigdecimal"

module Tungsten
  module Types
    module Int; end
    module Float; end
    module Decimal; end
    module Rational; end
    module String; end
    module Symbol; end
    module List; end
    module Map; end
    module Range; end
    module Bool; end
    module Nil; end
  end
end

Integer.include(Tungsten::Types::Int)
Float.include(Tungsten::Types::Float)
BigDecimal.include(Tungsten::Types::Decimal)
Rational.include(Tungsten::Types::Rational)
String.include(Tungsten::Types::String)
Symbol.include(Tungsten::Types::Symbol)
Array.include(Tungsten::Types::List)
Hash.include(Tungsten::Types::Map)
Range.include(Tungsten::Types::Range)
TrueClass.include(Tungsten::Types::Bool)
FalseClass.include(Tungsten::Types::Bool)
NilClass.include(Tungsten::Types::Nil)
