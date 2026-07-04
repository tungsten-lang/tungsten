# frozen_string_literal: true

require "tungsten/literals/quantity"
require "tungsten/support/units"

module Tungsten
  class Interpreter
    private

    def resolve_builtin_constant(name)
      case name.to_s
      when "π" then Math::PI
      when "τ" then Math::PI * 2
      when "ϕ", "φ" then (1 + Math.sqrt(5)) / 2.0
      when "ℯ" then Math::E
      when "ℇ" then 0.5772156649015329
      when "∞" then Float::INFINITY
      when "α" then 7.2973525643e-3
      when "ℎ" then physical_constant(6.62607015e-34, "J*s")
      when "ℏ" then physical_constant(1.054571817e-34, "J*s")
      when "c" then physical_constant(299_792_458, "m/s")
      when "G" then physical_constant(6.67430e-11, "m^3/kg*s^2")
      when "g₀" then physical_constant(9.80665, "m/s^2")
      when "Nₐ"
        unit = Units::CompoundUnit.new(
          dimension: Units::Dimension.new(0, 0, 0, 0, 0, -1, 0, 0),
          factor: 1.0,
          components: { "mol" => -1 }
        )
        Quantity.new(6.02214076e23, unit)
      when "kB" then physical_constant(1.380649e-23, "J/K")
      when "e₀" then physical_constant(1.602176634e-19, "C")
      when "R" then physical_constant(8.314462618, "J/mol*K")
      when "ε₀" then physical_constant(8.8541878188e-12, "F/m")
      when "μ₀", "µ₀" then physical_constant(1.25663706127e-6, "H/m")
      when "σ" then physical_constant(5.670374419e-8, "W/m^2*K^4")
      when "mₑ" then physical_constant(9.1093837139e-31, "kg")
      when "mₚ" then physical_constant(1.67262192595e-27, "kg")
      when "a₀" then physical_constant(5.29177210544e-11, "m")
      when "Eₕ" then physical_constant(4.3597447222060e-18, "J")
      when "Ry" then physical_constant(2.1798723611030e-18, "J")
      when "𝐹" then physical_constant(96_485.33212, "C/mol")
      else Environment::UNDEFINED
      end
    end

    def physical_constant(value, unit)
      Quantity.new(value, Units.parse(unit))
    end
  end
end
