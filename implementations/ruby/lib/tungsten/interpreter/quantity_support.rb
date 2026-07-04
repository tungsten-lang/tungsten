# frozen_string_literal: true

module Tungsten
  class Interpreter
    # Energy density for "burned X" conversions (energy → volume or mass).
    # :volume entries are J/m³, :mass entries are J/kg.
    # Use "burned" prefix to distinguish from mass-density (substance_mass) lookups.
    # `always_yield` substances skip the "burned" requirement — used for substances
    # whose value to humans is essentially their energy content (TNT, BOE, TCE).
    EnergyFuel = Struct.new(:density, :kind, :always_yield)
    ENERGY_FUELS = {
      # Liquid fuels (J/m³)
      "gasoline"    => EnergyFuel.new(34.2e9,  :volume, false),
      "diesel"      => EnergyFuel.new(38.6e9,  :volume, false),
      "jet fuel"    => EnergyFuel.new(34.7e9,  :volume, false),
      "ethanol"     => EnergyFuel.new(23.4e9,  :volume, false),
      "crude oil"   => EnergyFuel.new(38.49e9, :volume, true),  # tuned to 1 BOE = 6.12 GJ/barrel
      "crude"       => EnergyFuel.new(38.49e9, :volume, true),
      "oil"         => EnergyFuel.new(38.49e9, :volume, true),
      # Gases (J/m³ at STP)
      "natural gas" => EnergyFuel.new(38.3e6,  :volume, false),
      # Solids (J/kg for coal — TCE is mass-quoted; mass-based default for "1 tonne of coal")
      "coal"        => EnergyFuel.new(29.31e6, :mass,   true),  # TCE = 29.31 GJ/tonne
      "wood"        => EnergyFuel.new(9.5e9,   :volume, false),
      # Explosive yield (J/kg)
      "tnt"         => EnergyFuel.new(4.184e6, :mass,   true),  # 1 g TNT = 4184 J exact
      "TNT"         => EnergyFuel.new(4.184e6, :mass,   true),
      # Body composition (J/kg)
      "bodyfat"     => EnergyFuel.new(32.2e6,  :mass,   false),
      "body fat"    => EnergyFuel.new(32.2e6,  :mass,   false),
      # Fun ones
      "antimatter"  => EnergyFuel.new(1.8e21,  :volume, false),
      "chocolate"   => EnergyFuel.new(24.0e9,  :volume, false),
      "bacon"       => EnergyFuel.new(13.5e9,  :volume, false),
      "donuts"      => EnergyFuel.new(14.0e9,  :volume, false),
      "beer"        => EnergyFuel.new(1.7e9,   :volume, false)
    }.freeze

    private

    def visit_quantity_literal(node)
      value = evaluate(node.number)
      unit_str = node.unit_string

      # "burned cord" → create quantity with real unit, tag for energy conversion via "of"
      if unit_str.start_with?("burned ")
        real_unit_str = unit_str.sub(/\Aburned /, "")
        unit = Tungsten::Units.parse(real_unit_str)
        qty = Tungsten::Quantity.new(value, unit)
        qty.instance_variable_set(:@burned, true)
        return qty
      end

      unit = Tungsten::Units.parse(unit_str)
      Tungsten::Quantity.new(value, unit)
    end

    def convert_quantity_pipe(qty, node)
      # Multi-unit decomposition: quantity | [h, min, s]
      if node.is_a?(AST::ArrayLiteral)
        return decompose_quantity(qty, node.list)
      end

      # Extract display format from call like `unit(2)` or `unit(r)`
      fmt = nil
      if node.is_a?(AST::Call) && node.obj.nil? && node.args.size == 1
        arg = node.args[0]
        fmt = case arg
        when AST::Int then arg.value
        when AST::Var then arg.name == "r" ? :rational : nil
        end
        if fmt
          result = qty.convert_to(node.name)
          result.display_format = fmt
          return result
        end
      end

      unit_str = ast_to_unit_string(node)

      # Energy fuel conversion: "| burned gallons of gasoline"
      if qty.unit.dimension == Units::ENERGY && parse_energy_fuel(unit_str.downcase.gsub("_", " "))
        return substance_mass(qty, unit_str)
      end

      qty.convert_to(unit_str)
    end

    def decompose_quantity(qty, unit_nodes)
      si_value = qty.to_si
      results = []
      unit_nodes.each_with_index do |unode, i|
        unit_str = ast_to_unit_string(unode)
        target = Units.parse(unit_str)
        unless target.compatible?(qty.unit)
          raise DimensionError, "cannot decompose #{qty.unit} into #{unit_str}"
        end
        if i == unit_nodes.size - 1
          # Last unit gets the remainder (may be fractional)
          val = (si_value - target.offset) / target.factor
          results << Quantity.new(val, target)
        else
          # Integer part only, pass remainder to next unit
          val = ((si_value - target.offset) / target.factor).to_i
          results << Quantity.new(val, target)
          si_value -= val * target.factor + target.offset
        end
      end
      results
    end

    def ast_to_unit_string(node)
      case node
      when AST::Var
        node.name
      when AST::BinaryOp
        left = ast_to_unit_string(node.left)
        right = ast_to_unit_string(node.right)

        case node.operator
        when :/  then "#{left}/#{right}"
        when :*  then "#{left}*#{right}"
        when :** then "#{left}^#{right}"
        else raise Tungsten::Error, "invalid unit expression"
        end
      when AST::Call
        # Flatten nested calls: burned(gallons(of(gasoline))) → "burned gallons of gasoline"
        parts = [ node.name ]
        node.args.each { |a| parts << ast_to_unit_string(a) }
        parts.join(" ")
      when AST::Int
        node.value.to_s
      else
        raise Tungsten::Error, "invalid unit expression: #{node.class}"
      end
    end

    def substance_mass(qty, substance)
      normalized = substance.downcase.strip.gsub("_", " ")

      if normalized == "dark matter"
        require_relative "support/dark_matter"
        loop do
          STDOUT.puts Tungsten::DARK_MATTER_MESSAGES.sample
          sleep 10
        end
      end

      # Easter egg substances
      case normalized
      when "vacuum"
        return "shark or dyson?"
      when "ideas"
        return "i'm just a language, my ideas have no weight"
      when "happiness"
        return "couldn't find it either."
      when "electricity"
        return "watts the matter with you?"
      when "light"
        return "photons are massless. they don't even have baggage fees."
      when "windows"
        require_relative "support/dark_matter"
        STDOUT.puts Tungsten::BSOD_ART
        return nil
      when "tweets"
        require_relative "support/dark_matter"
        STDOUT.puts Tungsten::FAIL_WHALE_ART
        return nil
      end

      dim = qty.unit.dimension

      # Energy equivalents: "1 MJ of burned gallons of gasoline" → volume/mass
      if dim == Units::ENERGY
        fuel, output_unit, fuel_name = parse_energy_fuel(normalized)
        if fuel
          si_energy = (qty.value * qty.unit.factor).to_f
          label_suffix = " of #{fuel_name}"

          if fuel.kind == :mass
            # J/kg density → output in mass units
            kg = si_energy / fuel.density
            if output_unit
              sym, out_dim, out_factor = output_unit
              if out_dim != Units::MASS
                raise Tungsten::Error, "cannot convert '#{substance}' to volume units; try pounds or kg"
              end
            else
              sym, out_dim, out_factor = "kg", Units::MASS, 1.0
            end
            out = Units::CompoundUnit.new(
              dimension: out_dim, factor: out_factor, components: { "#{sym}#{label_suffix}" => 1 }
            )
            return Quantity.new((kg / out_factor).round(6), out)
          else
            # J/m³ density → output in volume units (or therms)
            m3 = si_energy / fuel.density
            if output_unit
              sym, out_dim, out_factor = output_unit
              if out_dim == Units::MASS
                raise Tungsten::Error,
                      "cannot convert volumetric fuel '#{substance}' to mass units; try gallons, liters, or barrels"
              end
              result = if out_dim == Units::ENERGY
                         si_energy / out_factor  # therms
              else
                         m3 / out_factor
              end
              out = Units::CompoundUnit.new(
                dimension: out_dim, factor: out_factor, components: { "#{sym}#{label_suffix}" => 1 }
              )
              return Quantity.new(result.round(6), out)
            else
              liters = m3 * 1000
              l_unit = Units::CompoundUnit.new(
                dimension: Units::VOLUME, factor: 0.001, components: { "L#{label_suffix}" => 1 }
              )
              return Quantity.new(liters.round(6), l_unit)
            end
          end
        end
      end

      # Reverse energy: "1 cord of burned wood" → volume × energy density = energy.
      # Substances with always_yield=true (TNT, oil, coal) skip the "burned" requirement —
      # their entire reason for being a unit is their energy content.
      yield_fuel_name = nil
      if normalized.start_with?("burned ")
        yield_fuel_name = normalized.sub(/\Aburned\s+/, "")
      else
        candidate = ENERGY_FUELS[normalized]
        yield_fuel_name = normalized if candidate&.always_yield
      end
      if yield_fuel_name
        fuel = ENERGY_FUELS[yield_fuel_name]
        if fuel
          if fuel.kind == :volume && dim == Units::VOLUME
            si_volume = (qty.value * qty.unit.factor).to_f
            joules = si_volume * fuel.density
            j_unit = Units::CompoundUnit.new(dimension: Units::ENERGY, factor: 1.0, components: { "J" => 1 })
            return Quantity.new(joules.round(6), j_unit)
          elsif fuel.kind == :mass && dim == Units::MASS
            si_mass = (qty.value * qty.unit.factor).to_f
            joules = si_mass * fuel.density
            j_unit = Units::CompoundUnit.new(dimension: Units::ENERGY, factor: 1.0, components: { "J" => 1 })
            return Quantity.new(joules.round(6), j_unit)
          end
        end
      end

      density = Units.lookup_density(substance)
      raise Tungsten::Error, "unknown substance '#{substance}'" unless density

      unless dim == Units::VOLUME
        dim_name = Units.dimension_name(dim)
        raise Tungsten::Error, "'of #{substance}' requires a volume quantity, got #{dim_name} (#{qty.unit})"
      end

      si_volume = (qty.value * qty.unit.factor).to_f
      mass_kg = si_volume * density
      kg_unit = Units::CompoundUnit.new(dimension: Units::MASS, factor: 1, components: { "kg" => 1 })
      Quantity.new(mass_kg.to_f, kg_unit)
    end

    # Parse "burned gallons of gasoline" → [EnergyFuel, output_unit_tuple_or_nil, substance_name]
    # Strips "burned", extracts optional output unit ("gallons", "barrels", etc.),
    # and looks up the substance in ENERGY_FUELS.
    def parse_energy_fuel(phrase)
      # Try "therms of natural gas" (no "burned" prefix, output unit is first word)
      if phrase =~ /\A(\w+)\s+of\s+(.+)\z/
        unit_word, substance = $1, $2
        output_unit = energy_output_units[unit_word]
        if output_unit && ENERGY_FUELS[substance]
          return [ ENERGY_FUELS[substance], output_unit, substance ]
        end
      end

      return nil unless phrase.start_with?("burned ")

      # Strip "burned " prefix
      rest = phrase.sub(/\Aburned\s+/, "")

      # Try "gallons of gasoline", "barrels of crude oil", "pounds of bodyfat"
      output_unit = nil
      if rest =~ /\A(\w+)\s+of\s+(.+)\z/
        unit_word, substance = $1, $2
        output_unit = energy_output_units[unit_word]
        rest = substance if output_unit
      end

      fuel = ENERGY_FUELS[rest]
      return nil unless fuel

      [ fuel, output_unit, rest ]
    end

    def energy_output_units
      require "tungsten/support/units"

      @energy_output_units ||= {
        "gallons" => [ "gal", Units::VOLUME, 3.785411784e-3 ],
        "gallon" => [ "gal", Units::VOLUME, 3.785411784e-3 ],
        "barrels" => [ "bbl", Units::VOLUME, 0.158987 ],
        "barrel" => [ "bbl", Units::VOLUME, 0.158987 ],
        "cords" => [ "cord", Units::VOLUME, 3.624556 ],
        "cord" => [ "cord", Units::VOLUME, 3.624556 ],
        "liters" => [ "L", Units::VOLUME, 0.001 ],
        "liter" => [ "L", Units::VOLUME, 0.001 ],
        "therms" => [ "therm", Units::ENERGY, 1.055e8 ],
        "therm" => [ "therm", Units::ENERGY, 1.055e8 ],
        "pounds" => [ "lb", Units::MASS, 0.45359237 ],
        "pound" => [ "lb", Units::MASS, 0.45359237 ],
        "kg" => [ "kg", Units::MASS, 1.0 ],
        "kilograms" => [ "kg", Units::MASS, 1.0 ]
      }.freeze
    end
  end
end
