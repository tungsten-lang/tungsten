# frozen_string_literal: true

module Tungsten
  class Interpreter
    W_SUBTAG_NAMES = {
      0x0 => "generic object",
      0x4 => "struct",
      0x5 => "hash",
      0x6 => "closure",
      0x7 => "regex",
      0x8 => "range",
      0x9 => "small array",
      0xA => "array",
      0xB => "string buffer",
      0xC => "class",
      0xD => "uuid",
      0xE => "error",
      0xF => "domain overflow"
    }.freeze

    W_NUMERIC_SUBTYPES = {
      0 => "decimal",
      1 => "currency",
      2 => "reserved",
      3 => "quantity"
    }.freeze

    W_PACKED_SUBTYPES = {
      0 => "color",
      1 => "complex",
      2 => "rational",
      3 => "reserved",
      4 => "date",
      5 => "ipv4",
      6 => "reserved",
      7 => "location"
    }.freeze

    W_CHAR_SUBTYPES = {
      0 => "token",
      1 => "lexchar",
      2 => "slice",
      3 => "char"
    }.freeze

    W_CHAR_CATEGORIES = %w[
      Lu Ll Lt Lm Lo
      Nd Nl No
      Zs Zl Zp
      Mn Mc Me
      Pc Pd Ps Pe Pi Pf Po
      Sm Sc Sk So
      Cc Cf Cs Co Cn
    ].freeze

    W_CURRENCY_SYMBOLS = {
      0  => "$",
      1  => "EUR",
      2  => "GBP",
      3  => "JPY",
      4  => "INR",
      5  => "CNY",
      6  => "KRW",
      7  => "BTC",
      8  => "CHF",
      9  => "CAD",
      10 => "AUD",
      11 => "BRL",
      12 => "RUB",
      13 => "THB",
      14 => "PLN"
    }.freeze

    W_CURRENCY_SYMBOL_IDS = {
      "$" => 0,
      "€" => 1, "EUR" => 1,
      "£" => 2, "GBP" => 2,
      "¥" => 3, "JPY" => 3,
      "₹" => 4, "INR" => 4,
      "CNY" => 5,
      "₩" => 6, "KRW" => 6,
      "₿" => 7, "BTC" => 7,
      "Fr" => 8, "CHF" => 8,
      "C$" => 9, "CAD" => 9,
      "A$" => 10, "AUD" => 10,
      "R$" => 11, "BRL" => 11,
      "₽" => 12, "RUB" => 12,
      "฿" => 13, "THB" => 13,
      "zł" => 14, "PLN" => 14
    }.freeze

    W_QUANTITY_UNIT_IDS = {
      "m" => 0, "kg" => 1, "s" => 2, "A" => 3, "K" => 4, "mol" => 5, "cd" => 6,
      "Hz" => 7, "N" => 8, "Pa" => 9, "J" => 10, "W" => 11, "C" => 12, "V" => 13,
      "F" => 14, "Ω" => 15, "S" => 16, "Wb" => 17, "T" => 18, "H" => 19, "°C" => 20,
      "lm" => 21, "lx" => 22, "Bq" => 23, "Gy" => 24, "Sv" => 25, "kat" => 26,
      "km" => 27, "cm" => 28, "mm" => 29, "µm" => 30, "nm" => 31, "pm" => 32,
      "g" => 33, "mg" => 34, "µg" => 35, "t" => 36, "ms" => 37, "µs" => 38,
      "ns" => 39, "ps" => 40, "kHz" => 41, "MHz" => 42, "GHz" => 43, "THz" => 44,
      "kJ" => 45, "MJ" => 46, "GJ" => 47, "kW" => 48, "MW" => 49, "GW" => 50,
      "kWh" => 51, "MWh" => 52, "mA" => 53, "µA" => 54, "kV" => 55, "MV" => 56,
      "kPa" => 57, "MPa" => 58, "GPa" => 59, "in" => 60, "ft" => 61, "yd" => 62,
      "mi" => 63, "oz" => 64, "lb" => 65, "fl oz" => 66, "gal" => 67, "qt" => 68,
      "pt" => 69, "m²" => 70, "cm²" => 71, "km²" => 72, "ha" => 73, "acre" => 74,
      "ft²" => 75, "m³" => 76, "cm³" => 77, "L" => 78, "mL" => 79, "m/s" => 80,
      "km/h" => 81, "mph" => 82, "m/s²" => 83, "rad" => 84, "°" => 85, "sr" => 86,
      "°F" => 87, "bit" => 88, "B" => 89, "KB" => 90, "MB" => 91, "GB" => 92,
      "TB" => 93, "PB" => 94, "KiB" => 95, "MiB" => 96, "GiB" => 97, "TiB" => 98,
      "J·s" => 99, "m³/(kg·s²)" => 100, "1/mol" => 101, "J/K" => 102, "J/(mol·K)" => 103,
      "F/m" => 104, "N/A²" => 105, "W/(m²·K⁴)" => 106, "eV" => 107, "cal" => 108,
      "kcal" => 109, "atm" => 110, "bar" => 111, "mbar" => 112, "Torr" => 113,
      "nmi" => 114, "ly" => 115, "au" => 116, "pc" => 117, "e₀" => 118, "%" => 0xFF
    }.freeze

    DIMENSION_AXES = [
      [ :length, "length", "m" ],
      [ :mass, "mass", "kg" ],
      [ :time, "time", "s" ],
      [ :current, "current", "A" ],
      [ :temperature, "temperature", "K" ],
      [ :substance, "substance", "mol" ],
      [ :luminosity, "luminosity", "cd" ],
      [ :information, "information", "B" ]
    ].freeze

    MOON_PHASES = [
      [ "\u{1F311}", "new moon" ],
      [ "\u{1F312}", "waxing crescent" ],
      [ "\u{1F313}", "first quarter" ],
      [ "\u{1F314}", "waxing gibbous" ],
      [ "\u{1F315}", "full moon" ],
      [ "\u{1F316}", "waning gibbous" ],
      [ "\u{1F317}", "last quarter" ],
      [ "\u{1F318}", "waning crescent" ]
    ].freeze

    CALENDAR_WEEKDAYS = %w[Su Mo Tu We Th Fr Sa].freeze
    CALENDAR_COLUMN_WIDTH = 5
    CALENDAR_LINE_WIDTH = ((CALENDAR_WEEKDAYS.size - 1) * CALENDAR_COLUMN_WIDTH) + 3
    DATE_SCENE_WIDTH = 80
    DATE_SCENE_RIGHT_COLUMN = 42
    DATE_SCENE_SEASON_SHIFT = 4

    UUID_VERSION_LABELS = {
      1 => "time-based",
      2 => "DCE security",
      3 => "name-based MD5",
      4 => "random",
      5 => "name-based SHA-1",
      6 => "reordered time",
      7 => "Unix timestamp",
      8 => "custom"
    }.freeze

    def inspect_wvalue_literal(raw)
      raw = raw.to_s.strip
      raise ArgumentError, "WValue literal must use exactly 16 hex digits" unless raw.match?(/\Au0x\h{16}\z/)

      bits = raw.delete_prefix("u0x").to_i(16)
      format_wvalue_breakdown(bits, raw: format("u0x%016X", bits))
    end

    def inspect_runtime_value(value)
      coerced = coerce_value_to_wvalue(value)

      lines = [
        inspection_header_line("result", inspection_value_label(value)),
        inspection_header_line("type", inspection_type_label(value))
      ]

      case value.class.name
      when "Tungsten::Quantity" then lines.concat(quantity_inspection_lines(value))
      when "Tungsten::Color" then lines.concat(color_inspection_lines(value))
      when "Tungsten::Date" then lines.concat(date_inspection_lines(value))
      when "Tungsten::DateTime" then lines.concat(date_time_inspection_lines(value))
      when "Tungsten::IP4" then lines.concat(ip4_inspection_lines(value))
      when "Tungsten::CIDR4" then lines.concat(cidr4_inspection_lines(value))
      when "Tungsten::UUID" then lines.concat(uuid_inspection_lines(value))
      end
      lines.concat(range_inspection_lines(value)) if value.is_a?(Range)
      lines.concat(array_inspection_lines(value)) if value.is_a?(::Array)
      lines.concat(hash_inspection_lines(value)) if value.is_a?(::Hash)

      if coerced[:bits]
        lines << format_wvalue_breakdown(coerced[:bits], raw: coerced[:raw], note: coerced[:note])
      else
        lines << inspection_header_line("wvalue", coerced[:note])
      end

      lines.join("\n")
    end

    def completion_names
      env_names = environment_names(@env)
      class_names = @classes.keys + @modules.keys
      unit_names = Units::UNIT_TABLE.keys + Units::UNIT_ALIASES.keys + W_QUANTITY_UNIT_IDS.keys
      (env_names + class_names + @builtins.keys + @method_builtins.keys + unit_names + BUILTIN_CONSTANT_NAMES).uniq.sort
    end

    def inline_signature_for(source)
      method_name = source.to_s[%r{[.#/]([[:alpha:]_][[:alnum:]_?!]*=?|[+\-*/%<>=!]+)\s*\(?\z}, 1]
      return nil unless method_name

      method_signature(method_name)
    end

    def method_reference(ref)
      match = ref.to_s.match(/\A([A-Z][\w:]*|\w+)#([^\s]+)\z/)
      return nil unless match

      class_name = match[1]
      method_name = match[2]
      method = @classes[class_name]&.lookup_method(method_name)
      builtin = @method_builtins[method_name]
      return nil unless method || builtin

      {
        ref: "#{class_name}##{method_name}",
        signature: method_signature(method_name, method),
        kind: method ? "Tungsten method" : "Ruby builtin bridge",
        location: method_source_location(method, builtin),
        source: method_source_excerpt(method, builtin),
        doc: method_doc_for(class_name, method_name)
      }
    end

    private

    def environment_names(env)
      names = []
      while env
        names.concat(env.bindings.keys)
        env = env.parent
      end
      names
    end

    def method_signature(method_name, method = nil)
      args = if method&.params
               method.params.map { |arg| method_arg_label(arg) }.join(", ")
      elsif method_name == "select"
               "&block"
      elsif method_name == "map" || method_name == "each"
               "&block"
      elsif method_name == "reduce"
               "initial = nil, &block"
      else
               "..."
      end
      "#{method_name}(#{args})"
    end

    def method_arg_label(arg)
      return arg.to_s unless arg.respond_to?(:name)

      name = arg.name.to_s
      name = "*#{name}" if arg.respond_to?(:splat?) && arg.splat?
      name
    end

    def method_source_location(method, builtin)
      if method&.body&.location
        loc = method.body.location
        return "#{project_relative_path(loc.file)}:#{loc.row}" if loc.file && loc.row
      end

      location = builtin&.source_location
      location ? "#{project_relative_path(location[0])}:#{location[1]}" : "unknown"
    end

    def project_relative_path(path)
      expanded = File.expand_path(path.to_s)
      root = project_root_for(expanded)
      prefix = "#{root}#{File::SEPARATOR}"
      expanded.start_with?(prefix) ? expanded.delete_prefix(prefix) : path.to_s
    rescue StandardError
      path.to_s
    end

    def project_root_for(path)
      dir = File.directory?(path) ? path : File.dirname(path)
      until dir == File.dirname(dir)
        return dir if File.directory?(File.join(dir, ".git")) || File.exist?(File.join(dir, "AGENTS.md"))

        dir = File.dirname(dir)
      end
      Dir.pwd
    end

    def method_source_excerpt(method, builtin)
      location = if method&.body&.location
                   loc = method.body.location
                   [ loc.file, loc.row ]
      else
                   builtin&.source_location
      end
      return [] unless location && location[0] && location[1] && File.file?(location[0])

      lines = File.readlines(location[0], chomp: true)
      start = [ location[1] - 2, 0 ].max
      lines[start, 6].to_a.map.with_index(start + 1) { |line, number| "#{number.to_s.rjust(4)} | #{line}" }
    rescue StandardError
      []
    end

    def method_doc_for(class_name, method_name)
      docs = {
        "Array#select" => "Returns a new Array containing elements for which the block is truthy.",
        "Array#map" => "Returns a new Array with each element replaced by the block result.",
        "Array#each" => "Calls the block for each element and returns the receiver.",
        "Array#reduce" => "Combines elements with a block, optionally starting from an initial value.",
        "Hash#keys" => "Returns an Array of keys.",
        "Hash#values" => "Returns an Array of values."
      }
      docs["#{class_name}##{method_name}"] || "No prose docs yet; source and signature are available."
    end

    def quantity_inspection_lines(quantity)
      unit = quantity.unit
      lines = [
        inspection_header_line("unit", quantity_unit_label(unit)),
        inspection_header_line("dimension", quantity_dimension_label(unit.dimension)),
        inspection_header_line("expanded", expanded_quantity_label(quantity))
      ]

      aliases = quantity_alias_labels(unit)
      lines << inspection_header_line("aliases", aliases) unless aliases.empty?

      conversions = quantity_conversion_labels(unit)
      lines << inspection_header_line("converts", conversions) unless conversions.empty?

      # Per-unit metadata: description / measured / year defined / source.
      sym = unit.canonical_symbol || unit.symbol
      def_obj = Tungsten::Units::UNIT_TABLE[sym]
      if def_obj
        if def_obj.respond_to?(:description) && def_obj.description
          lines << inspection_header_line("description", def_obj.description)
        end
        if def_obj.respond_to?(:measured) && !def_obj.measured.nil? &&
           (def_obj.respond_to?(:year_defined) && def_obj.year_defined ||
            def_obj.respond_to?(:defining_source) && def_obj.defining_source)
          status = def_obj.measured ? "measured" : "exact"
          parts = [ status ]
          parts << def_obj.year_defined.to_s if def_obj.year_defined
          parts << def_obj.defining_source if def_obj.defining_source
          lines << inspection_header_line("defined", parts.join(" — "))
        end
      end

      lines
    end

    def quantity_unit_label(unit)
      canonical = canonical_unit_symbol(unit)
      return unit.symbol unless canonical && canonical != unit.symbol

      "#{unit.symbol} (#{canonical})"
    end

    def quantity_dimension_label(dimension)
      name = dimension_name_label(dimension)
      signature = dimension_signature(dimension)
      return name if signature == name

      "#{name} (#{signature})"
    end

    def dimension_name_label(dimension)
      return "dimensionless" if dimension.dimensionless?

      Units.dimension_name(dimension)
    end

    def dimension_signature(dimension)
      return "dimensionless" if dimension.dimensionless?

      if dimension.custom?
        exp = dimension.custom_exp
        return dimension.custom_name if exp == 1

        return "#{dimension.custom_name}#{exponent_label(exp)}"
      end

      numerator = []
      denominator = []
      DIMENSION_AXES.each do |field, name, _unit|
        exp = dimension.public_send(field)
        next if exp.zero?

        target = exp.positive? ? numerator : denominator
        target << "#{name}#{exponent_label(exp.abs)}"
      end

      return numerator.join("\u00B7") if denominator.empty?
      return "1/#{denominator.join("\u00B7")}" if numerator.empty?

      "#{numerator.join("\u00B7")}/#{denominator.join("\u00B7")}"
    end

    def expanded_quantity_label(quantity)
      components = dimension_base_components(quantity.unit.dimension)
      return Quantity.new(quantity.to_si, dimensionless_unit).to_s.strip if components.empty?

      base_unit = Units::CompoundUnit.new(
        dimension: quantity.unit.dimension,
        factor: 1,
        components: components
      )
      Quantity.new(quantity.to_si, base_unit).to_s
    end

    def dimensionless_unit
      Units::CompoundUnit.new(dimension: Units::DIMENSIONLESS, factor: 1, components: {})
    end

    def dimension_base_components(dimension)
      return {} if dimension.dimensionless?
      return { dimension.custom_name => dimension.custom_exp } if dimension.custom?

      DIMENSION_AXES.each_with_object({}) do |(field, _name, unit), components|
        exp = dimension.public_send(field)
        components[unit] = exp unless exp.zero?
      end
    end

    def quantity_alias_labels(unit)
      canonical = canonical_unit_symbol(unit)
      return "" unless canonical

      aliases = Units::UNIT_ALIASES.select { |_label, target| target == canonical }.keys
      aliases = aliases.first(6) + [ "+ #{aliases.size - 6} more" ] if aliases.size > 6
      aliases.join(", ")
    end

    def quantity_conversion_labels(unit)
      current = [ unit.symbol, canonical_unit_symbol(unit) ].compact.uniq
      symbols = Units::UNIT_TABLE.each_with_object([]) do |(symbol, definition), list|
        next unless definition.dimension == unit.dimension
        next if current.include?(symbol)

        list << symbol
      end

      symbols = symbols.first(12) + [ "+ #{symbols.size - 12} more" ] if symbols.size > 12
      symbols.join(", ")
    end

    def canonical_unit_symbol(unit)
      return nil unless unit.components.size == 1

      symbol, exp = unit.components.first
      exp == 1 ? symbol : nil
    end

    def exponent_label(exp)
      return "" if exp == 1

      Units.exponent_to_superscript(exp).tr("-", "\u207B")
    end

    def color_inspection_lines(color)
      hue, saturation, lightness = rgb_to_hsl(color.r, color.g, color.b)
      luma = color_luma(color)
      contrast = luma > 128 ? "black text" : "white text"
      swatch = [ color.ansi_swatch("    "), color.ansi_swatch("    "), color.ansi_swatch("    ") ].join(" ")
      [
        inspection_header_line("swatch", swatch),
        inspection_header_line("rgba", "#{color.r}, #{color.g}, #{color.b}, #{color.a}"),
        inspection_header_line("hsl", "#{hue.round}\u00B0 #{(saturation * 100).round}% #{(lightness * 100).round}%"),
        inspection_header_line("luma", "#{format("%.1f", luma)} · #{contrast}"),
        inspection_header_line("red", "#{color_bar(color.r)} #{color.r}"),
        inspection_header_line("green", "#{color_bar(color.g)} #{color.g}"),
        inspection_header_line("blue", "#{color_bar(color.b)} #{color.b}"),
        inspection_header_line("alpha", "#{color_bar(color.a)} #{color.a}"),
        inspection_header_line(
          "palette",
          color_palette_line("complement", color_palette_color(hue + 180, saturation, lightness))
        ),
        inspection_header_line("", color_palette_line("triad", color_palette_color(hue + 120, saturation, lightness),
                                                       color_palette_color(hue + 240, saturation, lightness))),
        inspection_header_line("", color_palette_line("analogous", color_palette_color(hue - 30, saturation, lightness),
                                                           color_palette_color(hue + 30, saturation, lightness)))
      ]
    end

    def color_palette_line(label, *colors)
      chips = colors.map { |color| "#{color.ansi_swatch("  ")} #{color}" }.join("  ")
      "#{label.ljust(10)} #{chips}"
    end

    def color_palette_color(hue, saturation, lightness)
      r, g, b = hsl_to_rgb(hue, saturation, lightness)
      Color.new(r, g, b)
    end

    def hsl_to_rgb(hue, saturation, lightness)
      hue = (hue % 360) / 360.0
      if saturation.zero?
        value = (lightness * 255).round
        return [ value, value, value ]
      end

      q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - (lightness * saturation)
      p = (2 * lightness) - q
      [
        hue_channel_to_rgb(p, q, hue + (1.0 / 3)),
        hue_channel_to_rgb(p, q, hue),
        hue_channel_to_rgb(p, q, hue - (1.0 / 3))
      ].map { |channel| (channel * 255).round.clamp(0, 255) }
    end

    def hue_channel_to_rgb(p, q, t)
      t += 1 if t.negative?
      t -= 1 if t > 1
      return p + ((q - p) * 6 * t) if t < (1.0 / 6)
      return q if t < 0.5
      return p + ((q - p) * ((2.0 / 3) - t) * 6) if t < (2.0 / 3)

      p
    end

    def rgb_to_hsl(r, g, b)
      red = r / 255.0
      green = g / 255.0
      blue = b / 255.0
      max = [ red, green, blue ].max
      min = [ red, green, blue ].min
      lightness = (max + min) / 2.0
      return [ 0, 0, lightness ] if max == min

      delta = max - min
      saturation = lightness > 0.5 ? delta / (2.0 - max - min) : delta / (max + min)
      hue = case max
      when red then ((green - blue) / delta + (green < blue ? 6 : 0)) / 6.0
      when green then ((blue - red) / delta + 2) / 6.0
      else ((red - green) / delta + 4) / 6.0
      end
      [ hue * 360, saturation, lightness ]
    end

    def color_luma(color)
      (0.299 * color.r) + (0.587 * color.g) + (0.114 * color.b)
    end

    def color_bar(value, width = 16)
      filled = ((value / 255.0) * width).round
      "\u2588" * filled + "\u2591" * (width - filled)
    end

    def date_inspection_lines(date_value)
      date = date_value.value
      holiday = holiday_label(date)
      calendar = month_calendar_lines(date, zero_pad: true)
      right_panel = date_scene_right_panel(date, holiday)

      lines = [
        "",
        date_scene_header_line(date),
        date_scene_subheader_line(date, holiday),
        scene_line("")
      ]

      max_lines = [ calendar.length, right_panel.length ].max
      max_lines.times do |i|
        lines << scene_columns(calendar[i].to_s, right_panel[i].to_s)
      end
      lines << ""
      lines
    end

    def date_time_inspection_lines(date_time)
      value = date_time.value
      date = value.to_date
      [
        inspection_header_line("date", date.strftime("%A, %B %-d, %Y")),
        inspection_header_line("time", value.strftime("%H:%M:%S %:z")),
        inspection_header_line("ordinal", "day #{date.yday}/#{date.leap? ? 366 : 365} · ISO week #{date.cweek}"),
        inspection_header_line("season", season_label(date)),
        inspection_header_line("moon", moon_phase_label(date))
      ]
    end

    def block_lines(label, lines)
      return [] if lines.empty?

      [ inspection_header_line(label, lines.first) ] +
        lines.drop(1).map { |line| inspection_header_line("", line) }
    end

    def season_label(date)
      md = (date.month * 100) + date.day
      case md
      when 320..620 then "\u273F spring"
      when 621..921 then "\u2600 summer"
      when 922..1220 then "\u2619 autumn"
      else "\u2744 winter"
      end
    end

    def season_index(date)
      md = (date.month * 100) + date.day
      case md
      when 320..620 then 0
      when 621..921 then 1
      when 922..1220 then 2
      else 3
      end
    end

    def moon_phase_label(date)
      lunation = 29.530588853
      age = ((date.jd - 2_451_550.1) % lunation)
      phase_index = ((age / lunation) * 8).round % 8
      symbol, name = MOON_PHASES[phase_index]
      illumination = ((1 - Math.cos((2 * Math::PI * age) / lunation)) / 2 * 100).round
      "#{symbol} #{name} · age #{format("%.1f", age)}d · #{illumination}% lit"
    end

    def holiday_label(date)
      fixed = {
        [ 1, 1 ] => "\u2728 New Year's Day",
        [ 2, 14 ] => "\u2665 Valentine's Day",
        [ 3, 14 ] => "\u03C0 Pi Day",
        [ 3, 17 ] => "\u2618 St. Patrick's Day",
        [ 4, 1 ] => "\u203D April Fools' Day",
        [ 6, 19 ] => "\u2726 Juneteenth",
        [ 7, 4 ] => "\u2605 Independence Day",
        [ 10, 31 ] => "\u25B2 Halloween",
        [ 12, 25 ] => "\u2726 Christmas",
        [ 12, 31 ] => "\u2728 New Year's Eve"
      }
      fixed[[ date.month, date.day ]] || floating_holiday_label(date)
    end

    def holiday_scene_label(label)
      label.to_s.sub(/\A\S+\s+/, "")
    end

    def date_scene_header_line(date)
      title = "#{date.strftime("%A, %B")} #{date.day}#{ordinal_suffix(date.day)}, #{date.year}"
      day_week = "[Day #{date.yday}/#{date.leap? ? 366 : 365}] Week #{date.cweek}"
      season_rail = date_scene_season_rail(date)
      season_col = date_scene_season_column(title, day_week, season_rail)
      stats_col = DATE_SCENE_WIDTH - visible_length(day_week)

      line = blank_scene_line
      place_scene_text(line, 0, title)
      place_scene_text(line, season_col, season_rail)
      place_scene_text(line, stats_col, day_week)
      line
    end

    def date_scene_subheader_line(_date, holiday)
      line = blank_scene_line
      place_scene_text(line, 0, holiday_scene_label(holiday)) if holiday
      line
    end

    def date_scene_season_rail(date)
      case season_index(date)
      when 0 then "[\u273F] \u2600  \u2619  \u2744"
      when 1 then "\u273F [\u2600] \u2619  \u2744"
      when 2 then "\u273F  \u2600 [\u2619] \u2744"
      else "\u273F  \u2600  \u2619 [\u2744]"
      end
    end

    def date_scene_season_column(title, day_week, season_rail)
      stats_col = DATE_SCENE_WIDTH - visible_length(day_week)
      centered = ((DATE_SCENE_WIDTH - visible_length(season_rail)) / 2) + DATE_SCENE_SEASON_SHIFT
      left_bound = visible_length(title) + 2
      right_bound = stats_col - visible_length(season_rail) - 2
      [ [ centered, left_bound ].max, right_bound ].min
    end

    def date_scene_right_panel(date, holiday)
      holiday ? holiday_art(date) : []
    end

    def ordinal_suffix(day)
      return "th" if (11..13).include?(day % 100)

      case day % 10
      when 1 then "st"
      when 2 then "nd"
      when 3 then "rd"
      else "th"
      end
    end

    def scene_columns(left, right)
      return scene_line(left) if right.empty?

      padding = [ DATE_SCENE_RIGHT_COLUMN - visible_length(left), 1 ].max
      scene_line(left + (" " * padding) + right)
    end

    def scene_line(text)
      length = visible_length(text)
      return text if length >= DATE_SCENE_WIDTH

      text + (" " * (DATE_SCENE_WIDTH - length))
    end

    def blank_scene_line
      " " * DATE_SCENE_WIDTH
    end

    def place_scene_text(line, column, text)
      line[column, text.length] = text
    end

    def visible_length(text)
      text.to_s.gsub(/\e\[[0-9;]*m/, "").length
    end

    def floating_holiday_label(date)
      return "\u2696 Martin Luther King Jr. Day" if nth_weekday?(date, 1, 1, 3)
      return "\u273F Easter" if date == easter_date(date.year)
      return "\u2691 Memorial Day" if last_weekday?(date, 5, 1)
      return "\u2692 Labor Day" if nth_weekday?(date, 9, 1, 1)
      return "\u2606 Thanksgiving" if nth_weekday?(date, 11, 4, 4)

      nil
    end

    def easter_date(year)
      a = year % 19
      b = year / 100
      c = year % 100
      d = b / 4
      e = b % 4
      f = (b + 8) / 25
      g = (b - f + 1) / 3
      h = ((19 * a) + b - d - g + 15) % 30
      i = c / 4
      k = c % 4
      l = (32 + (2 * e) + (2 * i) - h - k) % 7
      m = (a + (11 * h) + (22 * l)) / 451
      month = (h + l - (7 * m) + 114) / 31
      day = ((h + l - (7 * m) + 114) % 31) + 1
      ::Date.new(year, month, day)
    end

    def nth_weekday?(date, month, weekday, nth)
      date.month == month && date.wday == weekday && ((date.day - 1) / 7) + 1 == nth
    end

    def last_weekday?(date, month, weekday)
      date.month == month && date.wday == weekday && (date + 7).month != month
    end

    def holiday_art(date)
      case [ date.month, date.day ]
      when [ 10, 31 ]
        halloween_pumpkin_art
      when [ 12, 25 ]
        christmas_tree_art
      when [ 3, 17 ]
        st_patricks_art
      when [ 7, 4 ]
        fourth_of_july_art
      when [ 2, 14 ]
        valentine_heart_art
      else
        return thanksgiving_art if nth_weekday?(date, 11, 4, 4)

        date == easter_date(date.year) ? easter_art : []
      end
    end

    def halloween_pumpkin_art
      orange = "38;5;208"
      yellow = "33"
      [
        "                   #{ansi_color("_", 32)}",
        "            #{ansi_color(".-\"\"\"\"\"\"\"-.", orange)}",
        "          #{ansi_color(".'", orange)}  #{ansi_color("/\\   /\\", yellow)}  #{ansi_color("'.", orange)}",
        "         #{ansi_color("/", orange)}      #{ansi_color("/_\\", yellow)}      #{ansi_color("\\", orange)}",
        "        #{ansi_color("|", orange)}    #{ansi_color("\\_/\\_/\\_/", yellow)}    #{ansi_color("|", orange)}",
        "         #{ansi_color("\\", orange)}    #{ansi_color("'--v--'", yellow)}    #{ansi_color("/", orange)}",
        [
          "  ", ansi_color("(___)", orange), "   ", ansi_color("(__)", orange),
          "      ", ansi_color("'._   _.'", orange)
        ].join
      ]
    end

    def christmas_lights_line
      [
        " ", ansi_color("o", 31), "--", ansi_color("o", 33), "--", ansi_color("o", 32),
        "--", ansi_color("o", 36), "--", ansi_color("o", 35), "--", ansi_color("o", 31),
        "--", ansi_color("o", 33), "--", ansi_color("o", 32)
      ].join
    end

    def christmas_tree_art
      [
        christmas_lights_line,
        "                         #{ansi_color("*", 33)}",
        "                        #{ansi_color("/_\\", 32)}",
        "                       #{ansi_color("/_", 32)}#{ansi_color("o", 31)}#{ansi_color("_\\", 32)}",
        [
          "                      ", ansi_color("/_", 32), ansi_color("o", 33),
          ansi_color("_", 32), ansi_color("o", 31), ansi_color("_\\", 32)
        ].join,
        [
          "                     ", ansi_color("/_", 32), ansi_color("o", 31),
          ansi_color("_", 32), ansi_color("o", 33), ansi_color("_", 32),
          ansi_color("o", 36), ansi_color("_\\", 32)
        ].join,
        "                    #{ansi_color("/_________\\", 32)}",
        "                        #{ansi_color("|_|", "38;5;94")}"
      ]
    end

    def st_patricks_art
      green = 32
      dark_green = "38;5;28"
      gold = 33
      pot = "38;5;94"
      red = 31
      orange = "38;5;208"
      blue = 34
      violet = 35
      [
        [
          " ", ansi_color("~~~~", red), ansi_color("~~~~", orange),
          ansi_color("~~~~", gold), ansi_color("~~~~", green),
          ansi_color("~~~~", blue), ansi_color("~~~~", violet)
        ].join,
        [
          "       ", ansi_color("\u2618", green), "             ", ansi_color("\u2618", green)
        ].join,
        [
          "          ", ansi_color("\u2618", green), "  ", ansi_color("\u2618", green),
          "  ", ansi_color("\u2618", green)
        ].join,
        "            #{ansi_color("\\ | /", dark_green)}",
        [
          "       ", ansi_color(".-======-.", pot), "  ", ansi_color("$", gold)
        ].join,
        [
          "      ", ansi_color("/", pot), " ", ansi_color("$ $ $ $", gold),
          " ", ansi_color("\\", pot)
        ].join,
        "      #{ansi_color("\\________/", pot)}"
      ]
    end

    def easter_art
      pink = 35
      yellow = 33
      cyan = 36
      [
        "                    #{ansi_color("(\\_/)", 37)}",
        "                    #{ansi_color("(o.o)", 37)}",
        "                    #{ansi_color("/ >\u{1F955}", 32)}",
        [
          "       ", ansi_color(".-.", pink), "      ", ansi_color(".-.", yellow),
          "      ", ansi_color(".-.", cyan)
        ].join,
        [
          "      ", ansi_color("/ ~ \\", pink), "    ", ansi_color("/ ^ \\", yellow),
          "    ", ansi_color("/ * \\", cyan)
        ].join,
        [
          "      ", ansi_color("\\___/", pink), "    ", ansi_color("\\___/", yellow),
          "    ", ansi_color("\\___/", cyan)
        ].join
      ]
    end

    def fourth_of_july_art
      red = 31
      white = 37
      blue = 34
      [
        [
          "  ", ansi_color("\\|/", red),
          "           ", ansi_color("\\|/", white),
          "                ", ansi_color("\\|/", blue)
        ].join,
        [
          " ", ansi_color("--", red), ansi_color("+", white), ansi_color("--", red),
          "        ", ansi_color("--", white), ansi_color("+", red), ansi_color("--", white),
          "              ", ansi_color("--", blue), ansi_color("+", white), ansi_color("--", blue)
        ].join,
        [
          "  ", ansi_color("/|\\", red),
          "           ", ansi_color("/|\\", white),
          "                ", ansi_color("/|\\", blue)
        ].join
      ]
    end

    def valentine_heart_art
      red = 31
      pink = "38;5;205"
      magenta = 35
      paper = 37
      [
        [
          "      ", ansi_color("♥", magenta), "                         ", ansi_color("♥", red)
        ].join,
        "                 #{ansi_color("♥♥", pink)}     #{ansi_color("♥♥", red)}",
        [
          "    ", ansi_color(".----.", paper), "     ",
          ansi_color("♥♥♥♥♥", pink), " ", ansi_color("♥♥♥♥♥", red)
        ].join,
        [
          "    ", ansi_color("|love|", paper), "    ",
          ansi_color("♥♥♥♥♥♥♥♥♥♥♥♥♥", red)
        ].join,
        [
          "    ", ansi_color("'----'", paper), "     ",
          ansi_color("♥♥♥♥♥♥♥♥♥♥♥", pink)
        ].join,
        "      #{ansi_color("♥", red)}          #{ansi_color("♥♥♥♥♥♥♥", magenta)}",
        "                   #{ansi_color("♥♥♥", magenta)}",
        "                    #{ansi_color("♥", magenta)}"
      ]
    end

    def thanksgiving_art
      brown = "38;5;130"
      trunk = "38;5;94"
      red = "38;5;196"
      orange = "38;5;208"
      gold = "38;5;214"
      yellow = "38;5;220"
      green = "38;5;142"
      purple = "38;5;165"

      [
        [
          "  ", ansi_color("^^^", red), "  ", ansi_color("^^^", orange),
          "       ", ansi_color(".-^-.", gold)
        ].join,
        [
          " ", ansi_color("^^^^^", orange), " ", ansi_color("^^^^^", yellow),
          "    ", ansi_color(".-'", green), " ", ansi_color("\\", orange),
          ansi_color("|", yellow), ansi_color("/", red), " ", ansi_color("'-.", purple)
        ].join,
        [
          "  ", ansi_color("||", trunk), "    ", ansi_color("||", trunk),
          "    ", ansi_color(".'", red), " ", ansi_color("\\", orange),
          "  ", ansi_color("|", gold), "  ", ansi_color("/", yellow),
          " ", ansi_color("'.", purple)
        ].join,
        [
          "            ", ansi_color("--=", gold), "  ", ansi_color("(o o)", brown),
          "  ", ansi_color("=--", gold)
        ].join,
        "                 #{ansi_color("\\ v /", yellow)}",
        "               #{ansi_color("/( : )\\", brown)}",
        "                #{ansi_color("/|\\", brown)}",
        "               #{ansi_color("/_|_\\", brown)}"
      ]
    end

    def ansi_color(text, code)
      "\e[#{code}m#{text}\e[0m"
    end

    def month_calendar_lines(date, zero_pad: false)
      first = ::Date.new(date.year, date.month, 1)
      last = ::Date.new(date.year, date.month, -1)
      lines = [ calendar_header_line, calendar_separator_line ]
      week = Array.new(first.wday, "    ")

      (first..last).each do |day|
        week << [ day.wday, day.day, day.day == date.day, zero_pad ]
        if day.wday == 6
          lines << calendar_week_line(week)
          week = []
        end
      end

      lines << calendar_week_line(week) unless week.empty?
      lines
    end

    def calendar_header_line
      line = blank_calendar_line
      CALENDAR_WEEKDAYS.each_with_index do |day, wday|
        line[calendar_column(wday), day.length] = day
      end
      line.rstrip
    end

    def calendar_separator_line
      "-" * CALENDAR_LINE_WIDTH
    end

    def calendar_week_line(week)
      line = blank_calendar_line
      week.each do |entry|
        next if entry.is_a?(String)

        wday, day, current, zero_pad = entry
        calendar_place_day(line, wday, day, current: current, zero_pad: zero_pad)
      end
      line.rstrip
    end

    def calendar_place_day(line, wday, day, current:, zero_pad:)
      column = calendar_column(wday)
      text = zero_pad ? format("%02d", day) : day.to_s.rjust(2)
      line[column, text.length] = text
      return unless current

      if column.zero?
        line[column, text.length + 2] = "[#{text}]"
      else
        line[column - 1] = "["
        line[column + text.length] = "]"
      end
    end

    def calendar_column(wday)
      wday * CALENDAR_COLUMN_WIDTH
    end

    def blank_calendar_line
      " " * CALENDAR_LINE_WIDTH
    end

    def ip4_inspection_lines(ip)
      octets = ip4_octets(ip)
      int = ip4_to_i(octets)
      [
        inspection_header_line("class", ip4_class_label(octets)),
        inspection_header_line("hex", format("0x%08X", int)),
        inspection_header_line("binary", octets.map { |octet| format("%08b", octet) }.join(".")),
        inspection_header_line("ptr", "#{octets.reverse.join(".")}.in-addr.arpa")
      ]
    end

    def cidr4_inspection_lines(cidr)
      ipaddr = cidr.value
      prefix = ipaddr.respond_to?(:prefix) ? ipaddr.prefix : cidr.to_s.scan(%r{/(\d+)}).flatten.first&.to_i
      prefix ||= 32
      addr = ip4_to_i(ip4_octets(cidr))
      mask = prefix.zero? ? 0 : (0xFFFF_FFFF << (32 - prefix)) & 0xFFFF_FFFF
      network = addr & mask
      broadcast = network | (~mask & 0xFFFF_FFFF)
      host_count = if prefix < 31
                     (2**(32 - prefix)) - 2
      elsif prefix == 31
                     2
      else
                     1
      end

      [
        inspection_header_line("prefix", "/#{prefix}"),
        inspection_header_line("netmask", i_to_ip4(mask)),
        inspection_header_line("network", i_to_ip4(network)),
        inspection_header_line("broadcast", i_to_ip4(broadcast)),
        inspection_header_line("hosts", host_count.to_s),
        inspection_header_line("range", cidr_host_range_label(network, broadcast, prefix)),
        inspection_header_line("diagram", cidr_diagram(prefix))
      ]
    end

    def ip4_octets(ip)
      ip.to_s.split(".").map(&:to_i)
    end

    def ip4_to_i(octets)
      octets.reduce(0) { |memo, octet| (memo << 8) | octet }
    end

    def i_to_ip4(int)
      [ 24, 16, 8, 0 ].map { |shift| (int >> shift) & 0xFF }.join(".")
    end

    def ip4_class_label(octets)
      first = octets[0]
      private_network = first == 10 ||
                        (first == 172 && octets[1].between?(16, 31)) ||
                        (first == 192 && octets[1] == 168)
      return "private RFC1918" if private_network
      return "loopback" if first == 127
      return "link-local" if first == 169 && octets[1] == 254
      return "multicast" if first.between?(224, 239)
      return "reserved" if first >= 240
      return "Class A public" if first < 128
      return "Class B public" if first < 192

      "Class C public"
    end

    def cidr_host_range_label(network, broadcast, prefix)
      first = prefix < 31 ? network + 1 : network
      last = prefix < 31 ? broadcast - 1 : broadcast
      "#{i_to_ip4(first)} .. #{i_to_ip4(last)}"
    end

    def cidr_diagram(prefix)
      network_bits = "\u2588" * (prefix / 2)
      host_bits = "\u2591" * ((32 - prefix) / 2)
      "#{network_bits}#{host_bits} #{prefix} network bits"
    end

    def uuid_inspection_lines(uuid)
      text = uuid.to_s.downcase
      hex = text.delete("-")
      version = hex[12].to_i(16)
      variant_nibble = hex[16].to_i(16)
      lines = [
        inspection_header_line("version", "v#{version} #{UUID_VERSION_LABELS[version] || "unknown"}"),
        inspection_header_line("variant", uuid_variant_label(variant_nibble)),
        inspection_header_line("layout", "8-4-4-4-12 hex nibbles"),
        inspection_header_line("urn", "urn:uuid:#{text}")
      ]

      if version == 7
        ms = hex[0, 12].to_i(16)
        lines << inspection_header_line("time", Time.at(ms / 1000.0).utc.strftime("%Y-%m-%d %H:%M:%S.%L UTC"))
      end

      lines
    end

    def uuid_variant_label(nibble)
      case nibble
      when 0..7 then "0xxx NCS"
      when 8..11 then "10xx RFC 4122 / RFC 9562"
      when 12..13 then "110x Microsoft"
      else "111x reserved"
      end
    end

    def range_inspection_lines(range)
      return [] unless range.begin.is_a?(Integer) && range.end.is_a?(Integer)

      size = range.size
      diagram_values = range.first(8)
      diagram = diagram_values.join(" \u2500 ")
      diagram << " \u2026 #{range.end}" if size && size > diagram_values.size
      [
        inspection_header_line("shape", range.exclude_end? ? "exclusive" : "inclusive"),
        inspection_header_line("size", size ? size.to_s : "unknown"),
        inspection_header_line("diagram", diagram)
      ]
    end

    def array_inspection_lines(array)
      lines = [ inspection_header_line("size", array.length.to_s) ]
      return lines if array.empty? || array.length > 80

      if (small = small_array_candidate(array))
        lines << inspection_header_line("layout", "SmallArray candidate · #{small[:label]} · #{small[:bytes]} bytes")
        lines << inspection_header_line("lowering", "normal Array unless compiler marks literal const_safe")
      end
      lines << inspection_header_line("spark", array_sparkline(array)) if array.all? { |item| item.is_a?(Numeric) }
      lines
    end

    def small_array_candidate(array)
      return nil unless array.length.between?(1, 255)
      return nil unless array.all? { |item| item.is_a?(Integer) && item.between?(0, 255) }

      {
        ebits: 8,
        label: "u8[#{array.length}]",
        bytes: 2 + array.length
      }
    end

    def array_sparkline(array)
      return "" if array.empty?

      values = array.map(&:to_f)
      min = values.min
      max = values.max
      ticks = "\u2581\u2582\u2583\u2584\u2585\u2586\u2587\u2588".chars
      return ticks.first * array.length if min == max

      values.map do |value|
        index = (((value - min) / (max - min)) * (ticks.length - 1)).round
        ticks[index]
      end.join
    end

    def hash_inspection_lines(hash)
      lines = [ inspection_header_line("size", hash.length.to_s) ]
      return lines if hash.empty?

      rows = hash.first(6).map { |key, value| [ compact_cell(key), compact_cell(value) ] }
      key_width = [ [ rows.map { |row| visible_length(row[0]) }.max || 3, 3 ].max, 22 ].min
      value_width = 80 - 13 - key_width
      lines << inspection_header_line("table", "#{fit_cell("key", key_width)} value")
      rows.each do |key, value|
        lines << inspection_header_line("", "#{fit_cell(key, key_width)} #{truncate_visible(value, value_width)}")
      end
      lines << inspection_header_line("", "... #{hash.length - rows.length} more") if hash.length > rows.length
      lines
    end

    def compact_cell(value)
      case value
      when String then value.inspect
      when Symbol then ":#{value}"
      else value.inspect
      end
    end

    def fit_cell(text, width)
      truncate_visible(text, width).ljust(width)
    end

    def truncate_visible(text, width)
      plain = text.to_s
      return plain if visible_length(plain) <= width
      return plain[0, width] if width <= 1

      "#{plain[0, width - 1]}\u2026"
    end

    def coerce_value_to_wvalue(value)
      case value
      when Runtime::RawWValue
        { bits: value.bits, raw: value.raw, note: nil }
      when NilClass
        exact_wvalue(W_NIL, "exact immediate encoding")
      when FalseClass
        exact_wvalue(W_FALSE, "exact immediate encoding")
      when TrueClass
        exact_wvalue(W_TRUE, "exact immediate encoding")
      when Integer
        coerce_integer_to_wvalue(value)
      when Float
        exact_wvalue(box_float_wvalue(value), "exact immediate encoding")
      when BigDecimal
        coerce_decimal_to_wvalue(value)
      when Rational
        coerce_rational_to_wvalue(value)
      when Symbol
        coerce_stringy_to_wvalue(value.to_s, is_symbol: true)
      when String
        coerce_stringy_to_wvalue(value, is_symbol: false)
      when Color
        coerce_color_to_wvalue(value)
      when Date
        coerce_date_to_wvalue(value)
      when DateTime
        coerce_date_time_to_wvalue(value)
      when CIDR4
        coerce_cidr4_to_wvalue(value)
      when IP4
        coerce_ip4_to_wvalue(value)
      when Currency
        coerce_currency_to_wvalue(value)
      when Percentage
        coerce_percentage_to_wvalue(value)
      when Quantity
        coerce_quantity_to_wvalue(value)
      when Duration
        coerce_duration_to_wvalue(value)
      when ::Array
        coerce_array_to_wvalue(value)
      else
        unsupported_wvalue("#{value.class.name} has no known exact immediate WValue encoding in wit")
      end
    end

    def coerce_integer_to_wvalue(value)
      if value < W_INT48_MIN || value > W_INT48_MAX
        return unsupported_wvalue("Integer #{value} does not fit Tungsten's 48-bit immediate int encoding")
      end

      exact_wvalue(W_TAG_INT | (value & W_PAYLOAD_MASK), "exact immediate encoding")
    end

    def coerce_stringy_to_wvalue(text, is_symbol:)
      bytes = text.to_s.b
      kind = is_symbol ? "symbol" : "string"
      if bytes.bytesize > 5
        return unsupported_wvalue(
          "#{kind.capitalize} #{text.inspect} is not self-contained; Tungsten may represent it as slab or heap"
        )
      end

      bits = W_TAG_STRINGSYM | (bytes.bytesize << 1)
      bytes.bytes.each_with_index do |byte, index|
        bits |= byte << (4 + 8 * index)
      end
      bits |= 1 if is_symbol

      exact_wvalue(bits, "exact immediate encoding")
    end

    def coerce_decimal_to_wvalue(value)
      sig, scale = decimal_sig_scale(value)
      unless sig
        return unsupported_wvalue("#{value.inspect} cannot be reduced to a finite decimal significand and scale")
      end
      unless sig.between?(W_DECIMAL_SIG_MIN, W_DECIMAL_SIG_MAX) &&
             scale.between?(W_DECIMAL_SCALE_MIN, W_DECIMAL_SCALE_MAX)
        return unsupported_wvalue("#{value.to_s("F")} requires Tungsten's decimal heap-overflow representation")
      end

      bits = W_TAG_DECIMAL | (signed_payload(sig, 39) << 7) | signed_payload(scale, 7)
      exact_wvalue(bits, "exact immediate encoding")
    end

    def coerce_rational_to_wvalue(value)
      numerator = value.numerator
      denominator = value.denominator
      unless fits_signed_width?(numerator, 22) && denominator.between?(1, (1 << 22) - 1)
        return unsupported_wvalue("#{value} does not fit Tungsten's packed rational numerator/denominator fields")
      end

      bits = W_TAG_PACKED | (2 << 45) | (signed_payload(numerator, 22) << 22) | denominator
      exact_wvalue(bits, "exact immediate encoding")
    end

    def coerce_color_to_wvalue(color)
      channels = [ color.r, color.g, color.b, color.a ].map(&:to_i)
      unless channels.all? { |channel| channel.between?(0, 255) }
        return unsupported_wvalue("#{color} has a channel outside the packed 8-bit color range")
      end

      r, g, b, a = channels
      bits = W_TAG_PACKED | (r << 36) | (g << 28) | (b << 20) | (a << 12)
      exact_wvalue(bits, "exact immediate encoding")
    end

    def coerce_date_to_wvalue(date_value)
      date = date_value.value
      coerce_packed_date_fields(date.year, date.month, date.day, 0, 0, 0, 0)
    end

    def coerce_date_time_to_wvalue(date_time)
      value = date_time.value
      unless value.sec_fraction.zero?
        return unsupported_wvalue("#{date_time} has sub-second precision beyond Tungsten's packed date-time fields")
      end

      offset_hours = value.offset * 24
      unless offset_hours.denominator == 1
        return unsupported_wvalue(
          "#{date_time} has a non-hour timezone offset beyond Tungsten's packed date-time field"
        )
      end

      coerce_packed_date_fields(
        value.year, value.month, value.day,
        value.hour, value.min, value.sec, offset_hours.to_i
      )
    end

    def coerce_packed_date_fields(year, month, day, hour, minute, second, timezone)
      unless fits_signed_width?(year, 12)
        return unsupported_wvalue("Year #{year} is outside Tungsten's signed 12-bit packed date range")
      end
      unless timezone.between?(-32, 31)
        return unsupported_wvalue("Timezone offset #{timezone} is outside Tungsten's signed 6-bit packed date range")
      end

      bits = W_TAG_PACKED | (4 << 45) |
             (signed_payload(year, 12) << 32) | (month << 28) | (day << 23) |
             (hour << 18) | (minute << 12) | (second << 6) | signed_payload(timezone, 6)
      exact_wvalue(bits, "exact immediate encoding")
    end

    def coerce_ip4_to_wvalue(ip)
      coerce_packed_ip4(ip, 0)
    end

    def coerce_cidr4_to_wvalue(cidr)
      prefix = cidr.respond_to?(:prefix) ? cidr.prefix : nil
      prefix ||= cidr.value.respond_to?(:prefix) ? cidr.value.prefix : nil
      prefix ||= cidr.to_s.scan(%r{/(\d+)}).flatten.first&.to_i
      coerce_packed_ip4(cidr, prefix || 32)
    end

    def coerce_packed_ip4(ip, prefix)
      octets = ip4_octets(ip)
      unless octets.size == 4 && octets.all? { |octet| octet.between?(0, 255) } && prefix.between?(0, 32)
        return unsupported_wvalue("#{ip} is outside Tungsten's packed IPv4/CIDR range")
      end

      bits = W_TAG_PACKED | (5 << 45) | (ip4_to_i(octets) << 12) | (prefix << 6)
      exact_wvalue(bits, "exact immediate encoding")
    end

    def coerce_currency_to_wvalue(currency)
      symbol_id = W_CURRENCY_SYMBOL_IDS[currency.symbol]
      unless symbol_id
        return unsupported_wvalue("Currency symbol #{currency.symbol.inspect} has no 4-bit WValue currency id")
      end

      sig, scale = decimal_sig_scale(currency.value)
      return unsupported_wvalue("#{currency} cannot be reduced to a finite decimal significand and scale") unless sig
      unless sig.between?(W_CURRENCY_SIG_MIN, W_CURRENCY_SIG_MAX) &&
             scale.between?(W_CURRENCY_SCALE_MIN, W_CURRENCY_SCALE_MAX)
        return unsupported_wvalue("#{currency} requires Tungsten's currency heap-overflow representation")
      end

      bits = W_TAG_DECIMAL | (1 << 46) | (symbol_id << 42) |
             (signed_payload(sig, 37) << 5) | signed_payload(scale, 5)
      exact_wvalue(bits, "exact immediate encoding")
    end

    def coerce_percentage_to_wvalue(percentage)
      sig, scale = decimal_sig_scale(BigDecimal(percentage.value.to_s))
      return unsupported_wvalue("#{percentage} cannot be reduced to a finite decimal significand and scale") unless sig

      coerce_boxed_quantity_wvalue("%", sig, scale, percentage.to_s)
    end

    def coerce_quantity_to_wvalue(quantity)
      unit_symbol = wvalue_quantity_unit_symbol(quantity.unit)
      sig, scale = decimal_sig_scale(BigDecimal(quantity.value.to_s))
      return unsupported_wvalue("#{quantity} cannot be reduced to a finite decimal significand and scale") unless sig

      coerce_boxed_quantity_wvalue(unit_symbol, sig, scale, quantity.to_s)
    rescue ArgumentError
      unsupported_wvalue("#{quantity} cannot be reduced to a finite decimal significand and scale")
    end

    def coerce_boxed_quantity_wvalue(unit_symbol, sig, scale, label)
      unit_id = W_QUANTITY_UNIT_IDS[unit_symbol]
      return unsupported_wvalue("Quantity unit #{unit_symbol.inspect} has no runtime WValue unit id") unless unit_id
      unless sig.between?(W_QUANTITY_SIG_MIN, W_QUANTITY_SIG_MAX) &&
             scale.between?(W_DECIMAL_SCALE_MIN, W_DECIMAL_SCALE_MAX)
        return unsupported_wvalue("#{label} requires Tungsten's quantity heap-overflow representation")
      end

      bits = W_TAG_DECIMAL | (3 << 46) | (unit_id << 38) |
             (signed_payload(sig, 31) << 7) | signed_payload(scale, 7)
      exact_wvalue(bits, "exact immediate encoding")
    end

    def wvalue_quantity_unit_symbol(unit)
      canonical_unit_symbol(unit) || unit.symbol
    end

    def coerce_duration_to_wvalue(duration)
      ns = duration.seconds * 1_000_000_000
      if duration.months.zero? && ns.denominator == 1 && ns.to_i.between?(W_DURATION_NS_MIN, W_DURATION_NS_MAX)
        return exact_wvalue(W_TAG_DURATION | signed_payload(ns.to_i, 47), "exact immediate encoding")
      end

      ms = duration.seconds * 1_000
      if ms.denominator == 1 && ms >= 0 && ms.to_i <= 0xFFFF_FFFF &&
         duration.months.between?(W_DURATION_MONTHS_MIN, W_DURATION_MONTHS_MAX)
        bits = W_TAG_DURATION | (1 << 47) | (signed_payload(duration.months, 15) << 32) | ms.to_i
        return exact_wvalue(bits, "exact immediate encoding")
      end

      unsupported_wvalue("#{duration} is outside Tungsten's immediate duration encodings")
    end

    def coerce_array_to_wvalue(array)
      if (small = small_array_candidate(array))
        return unsupported_wvalue(
          "Array object pointer is not known in wit; compiler may lower this literal to " \
          "SmallArray #{small[:label]} (subtag 0x9)"
        )
      end

      unsupported_wvalue("Array object pointer is not known in wit; runtime Array uses object subtag 0xA")
    end

    def decimal_sig_scale(value)
      sign, digits, _base, exponent = value.split
      sig = digits.to_i * sign
      scale = exponent - digits.length
      normalize_sig_scale(sig, scale)
    rescue FloatDomainError
      nil
    end

    def normalize_sig_scale(sig, scale)
      return [ 0, 0 ] if sig.zero?

      while (sig % 10).zero? && scale < W_DECIMAL_SCALE_MAX
        sig /= 10
        scale += 1
      end

      [ sig, scale ]
    end

    def signed_payload(value, width)
      value & ((1 << width) - 1)
    end

    def fits_signed_width?(value, width)
      value.between?(-(1 << (width - 1)), (1 << (width - 1)) - 1)
    end

    def box_float_wvalue(value)
      return 0x7FF9_0000_0000_0000 if value.nan?

      ieee_bits = [ value ].pack("G").unpack1("Q>")
      ieee_bits + W_DOUBLE_BIAS
    end

    def exact_wvalue(bits, note)
      { bits: bits, raw: format("u0x%016X", bits), note: note }
    end

    def unsupported_wvalue(note)
      { bits: nil, raw: nil, note: note }
    end

    def format_wvalue_breakdown(bits, raw:, note: nil)
      lines = [
        raw,
        inspection_header_line("hex", raw.delete_prefix("u0x").scan(/.{4}/).join(" ")),
        inspection_header_line("binary", format("%064b", bits).scan(/.{16}/).join(" "))
      ]

      lines.concat(wvalue_breakdown_lines(bits))
      lines << inspection_field_line("note", nil, nil, note) if note
      lines.join("\n")
    end

    def wvalue_breakdown_lines(bits)
      case bits
      when W_NIL
        singleton_breakdown("nil", bits)
      when W_FALSE
        singleton_breakdown("false", bits)
      when W_TRUE
        singleton_breakdown("true", bits)
      when W_UNDEF
        singleton_breakdown("undef", bits)
      when W_MEMO_MISS
        singleton_breakdown("memo miss", bits)
      else
        return double_breakdown(bits) if w_value_double?(bits)
        return object_breakdown(bits) if wvalue_object_space?(bits)

        case bits & W_TAG_MASK
        when W_TAG_STRINGSYM then stringy_breakdown(bits)
        when W_TAG_INT then int_breakdown(bits)
        when W_TAG_INSTANT then instant_breakdown(bits)
        when W_TAG_CHAR then char_breakdown(bits)
        when W_TAG_DECIMAL then numeric_breakdown(bits)
        when W_TAG_PACKED then packed_breakdown(bits)
        when W_TAG_DURATION then duration_breakdown(bits)
        else
          [ inspection_field_line("tag", "bits 63..48", format("0x%04X", (bits >> 48) & 0xFFFF), "unknown") ]
        end
      end
    end

    def singleton_breakdown(name, bits)
      [
        inspection_field_line("space", "bits 63..48", format("0x%04X", (bits >> 48) & 0xFFFF), "singleton / sentinel"),
        inspection_field_line("value", "bits 3..0", format("0x%X", bits), name)
      ]
    end

    def object_breakdown(bits)
      subtag = bits & 0xF
      pointer = bits & ~0xF
      [
        inspection_field_line("space", "bits 63..48", "0x0000", "heap object / singleton space"),
        inspection_field_line("pointer", "bits 63..4", format("0x%016X", pointer), "16-byte aligned pointer payload"),
        inspection_field_line("subtag", "bits 3..0", format("0x%X", subtag), W_SUBTAG_NAMES[subtag] || "reserved")
      ]
    end

    def double_breakdown(bits)
      ieee_bits = bits - W_DOUBLE_BIAS
      value = decode_w_value_double(bits)
      [
        inspection_field_line("space", "bits 63..48", format("0x%04X", (bits >> 48) & 0xFFFF), "biased double"),
        inspection_field_line("bias", nil, format("0x%016X", W_DOUBLE_BIAS), "subtract to recover IEEE-754 bits"),
        inspection_field_line("ieee", "bits 63..0", format("0x%016X", ieee_bits), "unbiased IEEE-754 payload"),
        inspection_field_line("decoded", nil, nil, inspection_value_label(value))
      ]
    end

    def stringy_breakdown(bits)
      mode = (bits >> 1) & 0x7
      is_symbol = (bits & 1) == 1
      lines = [
        inspection_field_line("tag", "bits 63..48", "0xFFF9", "string / symbol"),
        inspection_field_line("kind", "bit 0", is_symbol ? "1" : "0", is_symbol ? "symbol" : "string"),
        inspection_field_line("mode", "bits 3..1", mode.to_s, stringy_mode_label(mode))
      ]

      case mode
      when 0..5
        bytes = mode.times.map { |index| (bits >> (4 + 8 * index)) & 0xFF }
        bytes.each_with_index do |byte, index|
          hi = 11 + (index * 8)
          lo = 4 + (index * 8)
          lines << inspection_field_line(
            "byte[#{index}]", "bits #{hi}..#{lo}", format("0x%02X", byte), byte_label(byte)
          )
        end
        unused_start = 4 + (mode * 8)
        if unused_start <= 47
          unused_width = 48 - unused_start
          unused = (bits >> unused_start) & ((1 << unused_width) - 1)
          lines << inspection_field_line(
            "unused", "bits 47..#{unused_start}", format("0x%X", unused), "spare inline payload"
          )
        end
        text = bytes.pack("C*").force_encoding(Encoding::UTF_8)
        lines << inspection_field_line("decoded", nil, nil, is_symbol ? ":#{text}" : text.inspect)
      when 6
        index = (bits >> 4) & 0xFF_FFFF
        lines << inspection_field_line("slab", "bits 27..4", format("0x%06X", index), "index #{index}")
        lines << inspection_field_line("decoded", nil, nil, "needs slab table to recover contents")
      when 7
        pointer = bits & 0x0000_FFFF_FFFF_FFF0
        lines << inspection_field_line("heap", "bits 47..4", format("0x%016X", pointer), "masked WString* / WSymbol*")
        lines << inspection_field_line("decoded", nil, nil, "needs live heap object to recover contents")
      end

      lines
    end

    def int_breakdown(bits)
      payload = bits & W_PAYLOAD_MASK
      [
        inspection_field_line("tag", "bits 63..48", "0xFFFA", "48-bit signed integer"),
        inspection_field_line("payload", "bits 47..0", format("0x%012X", payload), "int48 payload"),
        inspection_field_line("decoded", nil, nil, sign_extend(payload, 48).to_s)
      ]
    end

    def instant_breakdown(bits)
      payload = bits & W_PAYLOAD_MASK
      ms = sign_extend(payload, 48)
      lines = [
        inspection_field_line("tag", "bits 63..48", "0xFFFB", "instant"),
        inspection_field_line("payload", "bits 47..0", format("0x%012X", payload), "signed Unix milliseconds"),
        inspection_field_line("decoded", nil, nil, "#{ms} ms since Unix epoch")
      ]

      begin
        lines << inspection_field_line("utc", nil, nil, Time.at(ms / 1000.0).utc.strftime("%Y-%m-%d %H:%M:%S.%L UTC"))
      rescue RangeError
        nil
      end

      lines
    end

    def char_breakdown(bits)
      subtype = (bits >> 46) & 0x3
      lines = [
        inspection_field_line("tag", "bits 63..48", "0xFFFC", "lexical / char"),
        inspection_field_line("subtype", "bits 47..46", subtype.to_s, W_CHAR_SUBTYPES.fetch(subtype))
      ]

      case subtype
      when 0
        lines << inspection_field_line("flags", "bits 45..40", format("0x%02X", (bits >> 40) & 0x3F), "token flags")
        lines << inspection_field_line("type", "bits 39..32", format("0x%02X", (bits >> 32) & 0xFF), "token kind")
        lines << inspection_field_line("length", "bits 31..20", ((bits >> 20) & 0xFFF).to_s, "bytes")
        lines << inspection_field_line("offset", "bits 19..0", (bits & 0xF_FFFF).to_s, "buffer offset")
      when 1
        codepoint = (bits >> 18) & 0x1F_FFFF
        lines << inspection_field_line(
          "codepoint", "bits 38..18", format("U+%04X", codepoint), safe_codepoint_label(codepoint)
        )
        lines << inspection_field_line("utf8", "bits 17..16", (((bits >> 16) & 0x3) + 1).to_s, "bytes")
        lines << inspection_field_line(
          "category", "bits 15..11", ((bits >> 11) & 0x1F).to_s, category_label((bits >> 11) & 0x1F)
        )
        lines << inspection_field_line("digit", "bits 10..7", format("0x%X", (bits >> 7) & 0xF), "digit value nibble")
        lines << inspection_field_line("flags", "bits 6..0", format("0x%02X", bits & 0x7F), "lex flags")
      when 2
        lines << inspection_field_line("length", "bits 37..24", ((bits >> 24) & 0x3FFF).to_s, "bytes")
        lines << inspection_field_line("offset", "bits 23..0", (bits & 0xFF_FFFF).to_s, "slice offset")
      when 3
        codepoint = bits & 0x1F_FFFF
        digit = (bits >> 39) & 0xF
        lines << inspection_field_line(
          "emoji", "bit 45", ((bits >> 45) & 1).to_s, (((bits >> 45) & 1) == 1 ? "set" : "clear")
        )
        lines << inspection_field_line(
          "ascii", "bit 44", ((bits >> 44) & 1).to_s, (((bits >> 44) & 1) == 1 ? "set" : "clear")
        )
        lines << inspection_field_line(
          "printable", "bit 43", ((bits >> 43) & 1).to_s,
          (((bits >> 43) & 1) == 1 ? "set" : "clear")
        )
        lines << inspection_field_line(
          "digit", "bits 42..39", format("0x%X", digit), digit == 0xF ? "not a digit" : digit.to_s
        )
        lines << inspection_field_line("case", "bits 38..30", sign_extend((bits >> 30) & 0x1FF, 9).to_s, "case delta")
        lines << inspection_field_line("width", "bits 29..28", ((bits >> 28) & 0x3).to_s, "display width")
        lines << inspection_field_line(
          "category", "bits 27..23", ((bits >> 23) & 0x1F).to_s, category_label((bits >> 23) & 0x1F)
        )
        lines << inspection_field_line("utf8", "bits 22..21", (((bits >> 21) & 0x3) + 1).to_s, "bytes")
        lines << inspection_field_line(
          "codepoint", "bits 20..0", format("U+%04X", codepoint), safe_codepoint_label(codepoint)
        )
      end

      lines
    end

    def numeric_breakdown(bits)
      subtype = (bits >> 46) & 0x3
      lines = [
        inspection_field_line("tag", "bits 63..48", "0xFFFD", "numeric"),
        inspection_field_line("subtype", "bits 47..46", subtype.to_s, W_NUMERIC_SUBTYPES.fetch(subtype))
      ]

      case subtype
      when 0
        lines << inspection_field_line(
          "sig", "bits 45..7", sign_extend((bits >> 7) & 0x7F_FFFF_FFFF, 39).to_s, "39-bit significand"
        )
        lines << inspection_field_line("scale", "bits 6..0", sign_extend(bits & 0x7F, 7).to_s, "decimal scale")
      when 1
        symbol_id = (bits >> 42) & 0xF
        lines << inspection_field_line(
          "symbol", "bits 45..42", symbol_id.to_s, W_CURRENCY_SYMBOLS[symbol_id] || "reserved"
        )
        lines << inspection_field_line(
          "sig", "bits 41..5", sign_extend((bits >> 5) & 0x1F_FFFF_FFFF, 37).to_s, "37-bit significand"
        )
        lines << inspection_field_line("scale", "bits 4..0", sign_extend(bits & 0x1F, 5).to_s, "currency scale")
      when 3
        unit_id = (bits >> 38) & 0xFF
        lines << inspection_field_line(
          "unit", "bits 45..38", format("0x%02X", unit_id),
          unit_id == 0xFF ? "percent sentinel" : "unit id"
        )
        lines << inspection_field_line(
          "sig", "bits 37..7", sign_extend((bits >> 7) & 0x7FFF_FFFF, 31).to_s, "31-bit significand"
        )
        lines << inspection_field_line("scale", "bits 6..0", sign_extend(bits & 0x7F, 7).to_s, "quantity scale")
      else
        lines << inspection_field_line("decoded", nil, nil, "reserved numeric subtype")
      end

      lines
    end

    def packed_breakdown(bits)
      subtype = (bits >> 45) & 0x7
      lines = [
        inspection_field_line("tag", "bits 63..48", "0xFFFE", "packed"),
        inspection_field_line("subtype", "bits 47..45", subtype.to_s, W_PACKED_SUBTYPES.fetch(subtype))
      ]

      case subtype
      when 0
        lines << inspection_field_line("r", "bits 43..36", format("0x%02X", (bits >> 36) & 0xFF), nil)
        lines << inspection_field_line("g", "bits 35..28", format("0x%02X", (bits >> 28) & 0xFF), nil)
        lines << inspection_field_line("b", "bits 27..20", format("0x%02X", (bits >> 20) & 0xFF), nil)
        lines << inspection_field_line("a", "bits 19..12", format("0x%02X", (bits >> 12) & 0xFF), nil)
        lines << inspection_field_line("flags", "bits 11..0", format("0x%03X", bits & 0xFFF), "colorspace / flags")
      when 1
        lines << inspection_field_line(
          "real", "bits 43..28", sign_extend((bits >> 28) & 0xFFFF, 16).to_s, "significand"
        )
        lines << inspection_field_line("r_scale", "bits 27..22", sign_extend((bits >> 22) & 0x3F, 6).to_s, "scale")
        lines << inspection_field_line("imag", "bits 21..6", sign_extend((bits >> 6) & 0xFFFF, 16).to_s, "significand")
        lines << inspection_field_line("i_scale", "bits 5..0", sign_extend(bits & 0x3F, 6).to_s, "scale")
      when 2
        lines << inspection_field_line(
          "num", "bits 43..22", sign_extend((bits >> 22) & 0x3F_FFFF, 22).to_s, "numerator"
        )
        lines << inspection_field_line("den", "bits 21..0", (bits & 0x3F_FFFF).to_s, "denominator")
      when 4
        lines << inspection_field_line("year", "bits 43..32", sign_extend((bits >> 32) & 0xFFF, 12).to_s, nil)
        lines << inspection_field_line("month", "bits 31..28", ((bits >> 28) & 0xF).to_s, nil)
        lines << inspection_field_line("day", "bits 27..23", ((bits >> 23) & 0x1F).to_s, nil)
        lines << inspection_field_line("hour", "bits 22..18", ((bits >> 18) & 0x1F).to_s, nil)
        lines << inspection_field_line("minute", "bits 17..12", ((bits >> 12) & 0x3F).to_s, nil)
        lines << inspection_field_line("second", "bits 11..6", ((bits >> 6) & 0x3F).to_s, nil)
        lines << inspection_field_line("tz", "bits 5..0", sign_extend(bits & 0x3F, 6).to_s, "timezone offset")
      when 5
        addr = (bits >> 12) & 0xFFFF_FFFF
        lines << inspection_field_line("addr", "bits 43..12", format("0x%08X", addr), ipv4_label(addr))
        lines << inspection_field_line("cidr", "bits 11..6", ((bits >> 6) & 0x3F).to_s, nil)
        lines << inspection_field_line("flags", "bits 5..0", format("0x%02X", bits & 0x3F), nil)
      when 7
        mode = (bits >> 43) & 1
        lines << inspection_field_line("mode", "bit 43", mode.to_s, mode.zero? ? "point" : "file")
        if mode.zero?
          lines << inspection_field_line("x", "bits 42..22", sign_extend((bits >> 22) & 0x1F_FFFF, 21).to_s, nil)
          lines << inspection_field_line("y", "bits 21..0", sign_extend(bits & 0x3F_FFFF, 22).to_s, nil)
        else
          lines << inspection_field_line("file", "bits 42..29", ((bits >> 29) & 0x3FFF).to_s, "file id")
          lines << inspection_field_line("line", "bits 28..11", ((bits >> 11) & 0x3F_FFFF).to_s, nil)
          lines << inspection_field_line("col", "bits 10..0", (bits & 0x7FF).to_s, nil)
        end
      else
        lines << inspection_field_line("decoded", nil, nil, "reserved packed subtype")
      end

      lines
    end

    def duration_breakdown(bits)
      mode = (bits >> 47) & 1
      lines = [
        inspection_field_line("tag", "bits 63..48", "0xFFFF", "duration"),
        inspection_field_line("mode", "bit 47", mode.to_s, mode.zero? ? "nanoseconds" : "months + milliseconds")
      ]

      if mode.zero?
        lines << inspection_field_line(
          "ns", "bits 46..0", sign_extend(bits & 0x7FFF_FFFF_FFFF, 47).to_s, "signed nanoseconds"
        )
      else
        lines << inspection_field_line("months", "bits 46..32", sign_extend((bits >> 32) & 0x7FFF, 15).to_s, nil)
        lines << inspection_field_line("ms", "bits 31..0", (bits & 0xFFFF_FFFF).to_s, "unsigned milliseconds")
      end

      lines
    end

    def wvalue_object_space?(bits)
      bits >= 0x10 && (bits >> 48).zero? && bits < W_DOUBLE_BIAS
    end

    def stringy_mode_label(mode)
      case mode
      when 0..5 then "inline (#{mode} byte#{mode == 1 ? "" : "s"})"
      when 6 then "slab"
      when 7 then "heap"
      end
    end

    def byte_label(byte)
      if byte.between?(32, 126)
        byte.chr.inspect
      else
        "non-printable"
      end
    end

    def safe_codepoint_label(codepoint)
      [ codepoint ].pack("U").inspect
    rescue RangeError
      "invalid codepoint"
    end

    def category_label(index)
      W_CHAR_CATEGORIES[index] || "unknown"
    end

    def ipv4_label(addr)
      [ 24, 16, 8, 0 ].map { |shift| (addr >> shift) & 0xFF }.join(".")
    end

    def inspection_header_line(label, value)
      "  #{label.ljust(8)} #{value}"
    end

    def inspection_field_line(label, bit_range, raw, meaning)
      line = +"  #{label.ljust(8)} #{bit_range.to_s.ljust(12)} #{raw.to_s.ljust(18)}"
      line << " #{meaning}" if meaning
      line.rstrip
    end

    def inspection_value_label(value)
      case value
      when Runtime::RawWValue then value.raw
      when Color then "#{value.ansi_swatch} #{value}"
      when String then value.inspect
      when Symbol then ":#{value}"
      else value.inspect
      end
    end

    def inspection_type_label(value)
      case value
      when NilClass then "Nil"
      when TrueClass, FalseClass then "Boolean"
      when Integer then "Integer"
      when Float then "Float"
      when String then "String"
      when Symbol then "Symbol"
      when Runtime::RawWValue then "RawWValue"
      else value.class.name
      end
    end
  end
end
