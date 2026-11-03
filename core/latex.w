# LaTeX — safe, composable TeX source for mathematical and scientific values.
#
# This module emits source only. It never invokes a TeX engine, and core
# numeric/algebra types do not depend on it. `raw` is the sole trusted-source
# boundary; ordinary strings and document metadata are escaped by default.

use core/latex/profiles
use core/latex/math
use core/latex/validation

# Escaping, composable math primitives, value renderers, and paper fragments.
+ LaTeX
  # Explicitly trust caller-supplied TeX. Prefer the structured helpers below
  # for values or text that did not originate in source code. Raw fragments
  # intentionally carry no label/reference/citation provenance.
  -> .raw(source)
    LatexFragment.new(source.to_s)

  # Escape text in one pass so generated control sequences are not escaped a
  # second time. This is safe in ordinary TeX text and in \text{...}.
  -> .escape(value)
    text = value.to_s
    out = ""
    text.chars.each -> (character)
      if character == "\\"
        out += "\\textbackslash{}"
      elsif character == "{"
        out += "\\{"
      elsif character == "}"
        out += "\\}"
      elsif character == "$"
        out += "\\$"
      elsif character == "&"
        out += "\\&"
      elsif character == "#"
        out += "\\#"
      elsif character == "_"
        out += "\\_"
      elsif character == "%"
        out += "\\%"
      elsif character == "~"
        out += "\\textasciitilde{}"
      elsif character == "^"
        out += "\\textasciicircum{}"
      else
        out += character
    out

  -> .escape_text(value)
    escape(value)

  # Escaped document-mode text.
  -> .text(value)
    raw(escape(value))

  # Escaped prose inside a mathematical expression.
  -> .math_text(value)
    raw("\\text{" + escape(value) + "}")

  -> .coerce(value)
    return value if value.class_name == "LatexFragment"
    render(value)

  -> .concat(values)
    compose(values, raw(""))

  -> .compose(values, separator)
    raise "LaTeX.join needs an Array" if values.class_name != "Array"
    separator_fragment = separator
    if separator.class_name != "LatexFragment"
      separator_fragment = raw(escape(separator))
    parts = []
    fragments = []
    i = 0
    values.each -> (value)
      fragment = coerce(value)
      parts.push(fragment.source)
      fragments.push(separator_fragment) if i > 0
      fragments.push(fragment)
      i += 1
    LatexFragment.from_parts(parts.join(separator_fragment.source), fragments)

  -> .join(values, separator = nil)
    separator = raw(", ") if separator == nil
    compose(values, separator)

  -> .builder
    LatexBuilder.new

  -> .semantic(value)
    LatexMath.from(value)

  # Publication profiles are loaded through the separate profiles
  # orchestrator; the generic renderer has no venue-specific policy.
  -> .profile(name)
    LaTeXProfiles.fetch(name)

  -> .profile_names
    LaTeXProfiles.names

  # ---- safe identifiers and scalar values ----

  -> .ascii_letter?(byte)
    (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)

  -> .ascii_digit?(byte)
    byte >= 48 && byte <= 57

  -> .ascii_digits?(value)
    bytes = value.to_s.bytes
    return false if bytes.empty?
    bytes.each -> (byte)
      return false if !ascii_digit?(byte)
    true

  -> .safe_control_name?(value)
    text = value.to_s
    return false if text.empty?
    bytes = text.bytes
    i = 0
    while i < bytes.size
      if !ascii_letter?(bytes[i])
        return i == bytes.size - 1 && bytes[i] == 42
      i += 1
    true

  -> .safe_label?(value)
    text = value.to_s
    return false if text.empty?
    bytes = text.bytes
    i = 0
    while i < bytes.size
      byte = bytes[i]
      safe = ascii_letter?(byte) || ascii_digit?(byte)
      safe = safe || byte == 45 || byte == 46 || byte == 47
      safe = safe || byte == 58 || byte == 95
      return false if !safe
      i += 1
    true

  -> .validated_control_name(value, kind)
    text = value.to_s
    if !safe_control_name?(text)
      raise "unsafe LaTeX " + kind + " name: " + text
    text

  -> .validated_label(value)
    text = value.to_s
    raise "unsafe LaTeX label: " + text if !safe_label?(text)
    text

  -> .slice_text(value, start, length)
    characters = value.to_s.chars
    out = ""
    i = start
    finish = start + length
    while i < finish && i < characters.size
      out += characters[i]
      i += 1
    out

  -> .greek_symbol(text)
    return "\\alpha" if text == "alpha" || text == "α"
    return "\\beta" if text == "beta" || text == "β"
    return "\\gamma" if text == "gamma" || text == "γ"
    return "\\delta" if text == "delta" || text == "δ"
    return "\\epsilon" if text == "epsilon" || text == "ε"
    return "\\zeta" if text == "zeta" || text == "ζ"
    return "\\eta" if text == "eta" || text == "η"
    return "\\theta" if text == "theta" || text == "θ"
    return "\\kappa" if text == "kappa" || text == "κ"
    return "\\lambda" if text == "lambda" || text == "λ"
    return "\\mu" if text == "mu" || text == "μ"
    return "\\nu" if text == "nu" || text == "ν"
    return "\\xi" if text == "xi" || text == "ξ"
    return "\\pi" if text == "pi" || text == "π"
    return "\\rho" if text == "rho" || text == "ρ"
    return "\\sigma" if text == "sigma" || text == "σ"
    return "\\tau" if text == "tau" || text == "τ"
    return "\\phi" if text == "phi" || text == "φ"
    return "\\chi" if text == "chi" || text == "χ"
    return "\\psi" if text == "psi" || text == "ψ"
    return "\\omega" if text == "omega" || text == "ω"
    return "\\Gamma" if text == "Gamma" || text == "Γ"
    return "\\Delta" if text == "Delta" || text == "Δ"
    return "\\Theta" if text == "Theta" || text == "Θ"
    return "\\Lambda" if text == "Lambda" || text == "Λ"
    return "\\Xi" if text == "Xi" || text == "Ξ"
    return "\\Pi" if text == "Pi" || text == "Π"
    return "\\Sigma" if text == "Sigma" || text == "Σ"
    return "\\Phi" if text == "Phi" || text == "Φ"
    return "\\Psi" if text == "Psi" || text == "Ψ"
    return "\\Omega" if text == "Omega" || text == "Ω"
    nil

  -> .symbol_base(value)
    text = value.to_s
    greek = greek_symbol(text)
    return raw(greek) if greek != nil
    return number_string(text) if ascii_digits?(text)
    bytes = text.bytes
    if bytes.size == 1 && ascii_letter?(bytes[0])
      return raw(text)
    raw("\\mathrm{" + escape(text) + "}")

  -> .symbol(value)
    text = value.to_s
    pieces = text.split("_")
    if pieces.size == 2 && !pieces[0].empty? && !pieces[1].empty?
      base = symbol_base(pieces[0])
      return subscript(base, symbol_base(pieces[1]))
    symbol_base(text)

  -> .superscript_character?(character)
    chars = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹", "⁺", "⁻"]
    chars.include?(character)

  -> .superscript_ascii(character)
    return "0" if character == "⁰"
    return "1" if character == "¹"
    return "2" if character == "²"
    return "3" if character == "³"
    return "4" if character == "⁴"
    return "5" if character == "⁵"
    return "6" if character == "⁶"
    return "7" if character == "⁷"
    return "8" if character == "⁸"
    return "9" if character == "⁹"
    return "+" if character == "⁺"
    "-"

  -> .math_literal(value)
    characters = value.to_s.chars
    out = ""
    i = 0
    while i < characters.size
      character = characters[i]
      if superscript_character?(character)
        exponent = ""
        while i < characters.size && superscript_character?(characters[i])
          exponent += superscript_ascii(characters[i])
          i += 1
        out += "^{" + exponent + "}"
      else
        if character == "≈"
          out += "\\approx "
        elsif character == "×"
          out += "\\times "
        elsif character == "−"
          out += "-"
        elsif character == "·"
          out += "\\cdot "
        elsif character == "%"
          out += "\\%"
        elsif character == "_" || character == "#" || character == "&"
          out += "\\" + character
        elsif character == "\\" || character == "{" || character == "}" || character == "$"
          return math_text(value)
        else
          out += character
        i += 1
    raw(out)

  -> .number_string(value)
    text = value.to_s
    return raw("\\infty") if text == "Infinity" || text == "inf"
    return raw("-\\infty") if text == "-Infinity" || text == "-inf"
    return raw("\\mathrm{NaN}") if text == "NaN" || text == "nan"
    exponent_parts = text.include?("e") ? text.split("e") : text.split("E")
    if exponent_parts.size == 2 && !exponent_parts[0].empty? && !exponent_parts[1].empty?
      exponent = exponent_parts[1].to_i.to_s
      return raw(math_literal(exponent_parts[0]).source + "\\times 10^{" + exponent + "}")
    math_literal(text)

  -> .number(value)
    if value.class_name == "Rational"
      numerator = value.numerator
      denominator = value.denominator
      return number_string(numerator) if denominator == 1
      if numerator < 0
        return raw("-\\frac{" + number_string(numerator.abs).source + "}{" + number_string(denominator).source + "}")
      return raw("\\frac{" + number_string(numerator).source + "}{" + number_string(denominator).source + "}")
    number_string(value)

  -> .scalar?(value)
    name = value.class_name
    names = [
      "Integer", "Int", "BigInt", "Rational",
      "Float", "Float16", "Float32", "Float64", "Float80", "Float128", "Float256",
      "BF16", "BigDecimal", "Decimal", "Decimal32", "Decimal64", "Decimal128"
    ]
    names.include?(name)

  # ---- composable math primitives ----

  -> .group(value)
    fragment = coerce(value)
    LatexFragment.from_parts("{" + fragment.source + "}", [fragment])

  -> .parenthesize(value)
    fragment = coerce(value)
    LatexFragment.from_parts("\\left(" + fragment.source + "\\right)", [fragment])

  -> .bracket(value)
    fragment = coerce(value)
    LatexFragment.from_parts("\\left\[" + fragment.source + "\\right]", [fragment])

  -> .absolute(value)
    fragment = coerce(value)
    LatexFragment.from_parts("\\left|" + fragment.source + "\\right|", [fragment])

  -> .fraction(numerator, denominator)
    top = coerce(numerator)
    bottom = coerce(denominator)
    source = "\\frac{" + top.source + "}{" + bottom.source + "}"
    LatexFragment.from_parts(source, [top, bottom])

  -> .sqrt(value)
    fragment = coerce(value)
    LatexFragment.from_parts("\\sqrt{" + fragment.source + "}", [fragment])

  -> .superscript(base, exponent)
    base_fragment = coerce(base)
    exponent_fragment = coerce(exponent)
    source = base_fragment.source + "^{" + exponent_fragment.source + "}"
    LatexFragment.from_parts(source, [base_fragment, exponent_fragment])

  -> .subscript(base, index)
    base_fragment = coerce(base)
    index_fragment = coerce(index)
    source = base_fragment.source + "_{" + index_fragment.source + "}"
    LatexFragment.from_parts(source, [base_fragment, index_fragment])

  -> .command(name, argument)
    control = validated_control_name(name, "command")
    fragment = coerce(argument)
    source = "\\" + control + "{" + fragment.source + "}"
    LatexFragment.from_parts(source, [fragment])

  -> .operator(name)
    raw("\\operatorname{" + escape(name) + "}")

  -> .environment(name, body)
    environment_name = validated_control_name(name, "environment")
    body_fragment = coerce(body)
    source = "\\begin{" + environment_name + "}\n"
    source += body_fragment.source + "\n"
    source += "\\end{" + environment_name + "}"
    LatexFragment.from_parts(source, [body_fragment])

  # ---- structural value renderers ----

  -> .render(value)
    return value if value.class_name == "LatexFragment"
    return value.to_latex if value.class_name == "LatexMath"
    name = value.class_name
    return LaTeX.number(value) if LaTeX.scalar?(value)
    return LaTeX.symbol(value) if name == "Symbol"
    return LaTeX.math_text(value) if name == "String"
    return LaTeX.raw("\\mathrm{" + value.to_s + "}") if name == "Bool"
    return LaTeX.raw("\\varnothing") if name == "Nil"
    return LaTeX.expression(value) if name == "Expression"
    return LaTeX.polynomial(value) if name == "Polynomial"
    return LaTeX.polynomial_ring(value) if name == "PolynomialRing"
    return LaTeX.field(value) if name == "RationalField" || name == "FiniteField"
    return LaTeX.field(value) if name == "NumberField" || name == "SimpleExtensionField"
    if name == "NumberFieldElement" || name == "SimpleExtensionElement"
      return LaTeX.power_basis_element(value)
    return LaTeX.projective_point(value) if name == "ProjectivePoint"
    if name == "Interval" || name == "IntervalF64" || name == "CertifiedRealInterval"
      return LaTeX.interval(value)
    return LaTeX.quadrature_result(value) if name == "QuadratureResult"
    return LaTeX.complex(value) if name == "Complex" || name == "BigComplex"
    vector_names = [
      "Vector", "Vec2", "Vec3", "Vec4", "Quaternion", "Octonion", "Sedenion",
      "Trigintaduonion", "Sexagintaquatronion", "Centumduodetrigintanion",
      "Ducentiquinquagintasexion"
    ]
    return LaTeX.vector(value.components) if vector_names.include?(name)
    return LaTeX.matrix(value.to_dense) if name == "SparseMatrix"
    matrix_names = ["Matrix", "Mat", "Mat2", "Mat3", "Mat4"]
    return LaTeX.matrix(value) if matrix_names.include?(name)
    return LaTeX.matrix(value.components) if name == "Metric"
    return LaTeX.quantity(value) if name == "Quantity"
    return LaTeX.currency(value) if name == "Currency"
    return LaTeX.percentage(value) if name == "Percentage"
    if name == "Array"
      if value.size > 0 && value[0].class_name == "Array"
        return LaTeX.matrix(value)
      return LaTeX.array(value)
    LaTeX.math_text(value)

  -> .expression(value, parent_precedence = 0)
    operation = value.operation
    arguments = value.arguments
    return LaTeX.render(value.constant_value) if value.constant?
    return LaTeX.symbol(value.variable_text) if value.variable?
    if value.named_constant?
      constant_name = value.named_constant_name.to_s
      return LaTeX.raw("\\pi") if constant_name == "pi"
      return LaTeX.raw("\\mathrm{e}") if constant_name == "e"
      return LaTeX.raw("\\gamma")

    precedence = 40
    result = nil
    if operation == "add"
      precedence = 10
      parts = []
      arguments.each -> (argument)
        parts.push(LaTeX.expression(argument, 10).source)
      source = ""
      i = 0
      while i < parts.size
        part = parts[i]
        if i == 0
          source += part
        elsif part.starts_with?("-")
          source += " - " + LaTeX.slice_text(part, 1, part.size - 1)
        else
          source += " + " + part
        i += 1
      result = LaTeX.raw(source)
    elsif operation == "multiply"
      precedence = 20
      start = 0
      prefix = ""
      if arguments.size > 1 && arguments[0].constant?
        coefficient = arguments[0].constant_value
        if coefficient == -1
          prefix = "-"
          start = 1
      parts = []
      i = start
      while i < arguments.size
        parts.push(LaTeX.expression(arguments[i], 20).source)
        i += 1
      result = LaTeX.raw(prefix + parts.join("\\,"))
    elsif operation == "divide"
      precedence = 20
      result = LaTeX.fraction(
        LaTeX.expression(arguments[0], 0),
        LaTeX.expression(arguments[1], 0))
    elsif operation == "power"
      precedence = 30
      result = LaTeX.superscript(
        LaTeX.expression(arguments[0], 31),
        LaTeX.expression(arguments[1], 0))
    elsif operation == "sqrt"
      result = LaTeX.sqrt(LaTeX.expression(arguments[0], 0))
    elsif operation == "abs"
      result = LaTeX.absolute(LaTeX.expression(arguments[0], 0))
    else
      function = LaTeX.operator(operation)
      function = LaTeX.raw("\\Gamma") if operation == "gamma"
      function = LaTeX.raw("\\log\\Gamma") if operation == "log_gamma"
      function = LaTeX.raw("\\zeta") if operation == "zeta"
      function = LaTeX.raw("\\log") if operation == "log"
      arguments_rendered = []
      arguments.each -> (argument)
        arguments_rendered.push(LaTeX.expression(argument, 0))
      result = LaTeX.raw(
        function.source + LaTeX.parenthesize(LaTeX.join(arguments_rendered)).source)

    if precedence < parent_precedence
      return LaTeX.parenthesize(result)
    result

  -> .polynomial(value)
    return LaTeX.raw("0") if value.zero?
    field_value = value.ring.field
    terms = []
    value.each_term -> (coefficient, exponents)
      negative = false
      magnitude = coefficient
      if field_value.class_name == "RationalField" && field_value.negative?(coefficient)
        negative = true
        magnitude = field_value.negate(coefficient)

      factors = []
      i = 0
      while i < exponents.size
        exponent = exponents[i]
        if exponent > 0
          factor = LaTeX.symbol(value.ring.names[i])
          factor = LaTeX.superscript(factor, exponent) if exponent != 1
          factors.push(factor.source)
        i += 1
      monomial = factors.join("\\,")
      source = ""
      if monomial.empty? || !field_value.one?(magnitude)
        coefficient_source = field_value.class_name == "RationalField" ? LaTeX.render(magnitude).source : LaTeX.math_literal(field_value.element_to_s(magnitude)).source
        source += coefficient_source
        source += "\\," if !monomial.empty?
      source += monomial
      terms.push([negative, source])

    output = ""
    i = 0
    while i < terms.size
      negative = terms[i][0]
      source = terms[i][1]
      if i == 0
        output += negative ? "-" + source : source
      else
        output += negative ? " - " + source : " + " + source
      i += 1
    LaTeX.raw(output)

  -> .field(value)
    name = value.class_name
    return LaTeX.raw("\\mathbb{Q}") if name == "RationalField"
    return LaTeX.subscript(LaTeX.raw("\\mathbb{F}"), value.order) if name == "FiniteField"
    if name == "NumberField"
      return LaTeX.raw("\\mathbb{Q}" + LaTeX.parenthesize(LaTeX.symbol(value.name)).source)
    base = LaTeX.field(value.base_field)
    LaTeX.raw(base.source + LaTeX.parenthesize(LaTeX.symbol(value.name)).source)

  -> .polynomial_ring(value)
    names = []
    ring_names = value.names
    i = 0
    while i < ring_names.size
      names.push(LaTeX.symbol(ring_names[i]))
      i += 1
    LaTeX.raw(LaTeX.field(value.field).source + "\\left\[" + LaTeX.join(names).source + "\\right]")

  -> .power_basis_element(value)
    coefficients = value.coefficients
    coefficient_field = value.class_name == "NumberFieldElement" ? RationalField.new : value.field.base_field
    variable = LaTeX.symbol(value.field.name)
    terms = []
    i = 0
    while i < coefficients.size
      coefficient = coefficients[i]
      if !coefficient_field.zero?(coefficient)
        negative = false
        magnitude = coefficient
        if coefficient_field.class_name == "RationalField" && coefficient_field.negative?(coefficient)
          negative = true
          magnitude = coefficient_field.negate(coefficient)
        factor = ""
        if i > 0
          factor = i == 1 ? variable.source : LaTeX.superscript(variable, i).source
        source = ""
        if i == 0 || !coefficient_field.one?(magnitude)
          source += LaTeX.render(magnitude).source
          source += "\\," if i > 0
        source += factor
        terms.push([negative, source])
      i += 1
    return LaTeX.raw("0") if terms.empty?
    output = ""
    i = 0
    while i < terms.size
      if i == 0
        output += terms[i][0] ? "-" + terms[i][1] : terms[i][1]
      else
        output += terms[i][0] ? " - " + terms[i][1] : " + " + terms[i][1]
      i += 1
    LaTeX.raw(output)

  -> .projective_point(value)
    coordinates = []
    value.coordinates.each -> (coordinate)
      coordinates.push(LaTeX.render(coordinate))
    joined = LaTeX.join(coordinates, LaTeX.raw(":"))
    source = "\\left\[" + joined.source + "\\right]"
    LatexFragment.from_parts(source, [joined])

  -> .array(values)
    parts = []
    values.each -> (value)
      parts.push(LaTeX.render(value))
    joined = LaTeX.join(parts)
    source = "\\left\[" + joined.source + "\\right]"
    LatexFragment.from_parts(source, [joined])

  -> .vector(values)
    rows = []
    values.each -> (value)
      rows.push([value])
    LaTeX.matrix(rows)

  -> .matrix(value, environment_name = "bmatrix")
    environment = validated_control_name(environment_name, "matrix environment")
    allowed = ["matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "smallmatrix"]
    raise "unsupported LaTeX matrix environment: " + environment if !allowed.include?(environment)
    rows = []
    if value.class_name == "Array"
      value.each -> (row)
        raise "LaTeX.matrix rows must be Arrays" if row.class_name != "Array"
        rows.push(row)
    else
      r = 0
      while r < value.rows
        row = []
        c = 0
        while c < value.cols
          row.push(value.at(r, c))
          c += 1
        rows.push(row)
        r += 1
    raise "LaTeX.matrix needs at least one row" if rows.empty?
    width = rows[0].size
    raise "LaTeX.matrix needs at least one column" if width == 0
    rendered_rows = []
    rendered_cells = []
    rows.each -> (row)
      raise "LaTeX.matrix rows must have equal size" if row.size != width
      cells = []
      row.each -> (cell)
        rendered = LaTeX.render(cell)
        cells.push(rendered)
        rendered_cells.push(rendered)
      rendered_rows.push(LaTeX.join(cells, LaTeX.raw(" & ")).source)
    row_break = "\\\\"
    source = "\\begin{" + environment + "}"
    source += rendered_rows.join(" " + row_break + "\n")
    source += "\\end{" + environment + "}"
    LatexFragment.from_parts(source, rendered_cells)

  -> .interval(value)
    return math_text(value) if !value.respond_to?("lo") && !value.respond_to?("first")
    lower = value.respond_to?("lo") ? value.lo : value.first
    upper = value.respond_to?("hi") ? value.hi : value.last
    lower_fragment = render(lower)
    upper_fragment = render(upper)
    source = "\\left\[" + lower_fragment.source + ", "
    source += upper_fragment.source + "\\right]"
    LatexFragment.from_parts(source, [lower_fragment, upper_fragment])

  -> .quadrature_result(value)
    result = render(value.value)
    error = render(value.error_estimate)
    source = result.source + " \\pm " + error.source
    LatexFragment.from_parts(source, [result, error])

  -> .complex(value)
    real = value.real
    imaginary = value.imag
    return render(real) if imaginary == 0
    source = ""
    source += render(real).source if real != 0
    negative = imaginary.respond_to?("negative?") && imaginary.negative?
    magnitude = negative ? imaginary.abs : imaginary
    if !source.empty?
      source += negative ? " - " : " + "
    elsif negative
      source += "-"
    source += render(magnitude).source + "\\," if magnitude != 1
    raw(source + "\\mathrm{i}")

  -> .unit(value)
    characters = value.to_s.chars
    out = "\\mathrm{"
    i = 0
    while i < characters.size
      character = characters[i]
      if superscript_character?(character)
        exponent = ""
        while i < characters.size && superscript_character?(characters[i])
          exponent += superscript_ascii(characters[i])
          i += 1
        out += "^{" + exponent + "}"
      else
        if character == "·"
          out += "\\,\\cdot\\,"
        elsif character == "°"
          out += "{}^{\\circ}"
        elsif character == "μ" || character == "µ"
          out += "\\mu "
        elsif character == "Δ"
          out += "\\Delta "
        elsif character == "Ω"
          out += "\\Omega "
        elsif character == "%"
          out += "\\%"
        elsif character == "\\" || character == "{" || character == "}" || character == "$"
          out += escape(character)
        elsif character == "_" || character == "#" || character == "&"
          out += "\\" + character
        else
          out += character
        i += 1
    out += "}"
    raw(out)

  -> .quantity(value)
    display = value.to_s
    return percentage(value) if display.ends_with?("%")
    # Point/delta annotations currently expose no cross-engine magnitude/unit
    # accessors. Preserve them safely until that committed API is available.
    return math_text(display) if display.include?(").point(") || display.include?(").delta(")
    pieces = display.split(" ")
    return math_text(display) if pieces.size < 2
    unit_text = pieces[pieces.size - 1]
    magnitude_parts = []
    i = 0
    while i < pieces.size - 1
      magnitude_parts.push(pieces[i])
      i += 1
    magnitude = number_string(magnitude_parts.join(" "))
    raw(magnitude.source + "\\," + unit(unit_text).source)

  -> .currency(value)
    text = value.to_s
    symbol_value = nil
    symbol_value = "$" if text.starts_with?("$")
    symbol_value = "€" if text.starts_with?("€")
    symbol_value = "£" if text.starts_with?("£")
    symbol_value = "¥" if text.starts_with?("¥")
    symbol_value = "₹" if text.starts_with?("₹")
    symbol_value = "₩" if text.starts_with?("₩")
    symbol_value = "₽" if text.starts_with?("₽")
    symbol_value = "₿" if text.starts_with?("₿")
    return math_text(text) if symbol_value == nil
    amount = slice_text(text, symbol_value.size, text.size - symbol_value.size)
    raw("\\text{" + escape(symbol_value) + "}" + number_string(amount).source)

  -> .percentage(value)
    text = value.to_s
    if text.ends_with?("%")
      amount = slice_text(text, 0, text.size - 1)
      return raw(number_string(amount).source + "\\%")
    math_text(text)

  # ---- paper-oriented fragments ----

  -> .inline(value)
    fragment = render(value)
    LatexFragment.from_parts("\\(" + fragment.source + "\\)", [fragment])

  -> .display(value)
    fragment = render(value)
    source = "\\\[\n" + fragment.source + "\n\\]"
    LatexFragment.from_parts(source, [fragment])

  -> .label(value)
    key = validated_label(value)
    LatexFragment.new(
      "\\label{" + key + "}", [LatexReferenceEvent.new(:label, key)])

  -> .ref(value)
    key = validated_label(value)
    LatexFragment.new(
      "\\ref{" + key + "}", [LatexReferenceEvent.new(:ref, key)])

  -> .eqref(value)
    key = validated_label(value)
    LatexFragment.new(
      "\\eqref{" + key + "}", [LatexReferenceEvent.new(:eqref, key)])

  -> .equation(value, label_value = nil)
    rendered = render(value)
    parts = [rendered]
    source = "\\begin{equation}\n" + rendered.source
    if label_value != nil
      label_fragment = label(label_value)
      parts.push(label_fragment)
      source += "\n" + label_fragment.source
    source += "\n\\end{equation}"
    LatexFragment.from_parts(source, parts)

  -> .align(lines, label_value = nil)
    raise "LaTeX.align needs an Array" if lines.class_name != "Array"
    rendered = []
    lines.each -> (line)
      rendered.push(coerce(line))
    row_break = "\\\\"
    rendered_sources = []
    rendered.each -> (fragment)
      rendered_sources.push(fragment.source)
    parts = []
    rendered.each -> (fragment)
      parts.push(fragment)
    source = "\\begin{align}\n" + rendered_sources.join(" " + row_break + "\n")
    if label_value != nil
      label_fragment = label(label_value)
      parts.push(label_fragment)
      source += "\n" + label_fragment.source
    source += "\n\\end{align}"
    LatexFragment.from_parts(source, parts)

  -> .table_alignment(width, alignment)
    if alignment == nil
      out = ""
      width.times -> out += "c"
      return out
    text = alignment.to_s
    columns = 0
    text.bytes.each -> (byte)
      if byte == 108 || byte == 99 || byte == 114
        columns += 1
      elsif byte != 124
        raise "LaTeX table alignment accepts only l, c, r, and |"
    raise "LaTeX table alignment column count mismatch" if columns != width
    text

  -> .table_cell_fragment(value)
    name = value.class_name
    return value if name == "LatexFragment"
    return text(value) if name == "String" || name == "Symbol"
    rendered = render(value)
    LatexFragment.from_parts("$" + rendered.source + "$", [rendered])

  -> .table_cell(value)
    table_cell_fragment(value).source

  -> .tabular(headers, rows, alignment = nil)
    if headers.class_name != "Array" || headers.empty?
      raise "LaTeX.tabular needs a nonempty header Array"
    raise "LaTeX.tabular rows must be an Array" if rows.class_name != "Array"
    width = headers.size
    header_cells = []
    all_cells = []
    headers.each -> (cell)
      fragment = table_cell_fragment(cell)
      header_cells.push(fragment.source)
      all_cells.push(fragment)
    body_rows = []
    rows.each -> (row)
      if row.class_name != "Array" || row.size != width
        raise "LaTeX.tabular rows must match the header width"
      cells = []
      row.each -> (cell)
        fragment = table_cell_fragment(cell)
        cells.push(fragment.source)
        all_cells.push(fragment)
      body_rows.push(cells.join(" & "))
    row_break = "\\\\"
    source = "\\begin{tabular}{" + table_alignment(width, alignment) + "}\n"
    source += "\\hline\n" + header_cells.join(" & ") + " " + row_break + "\n"
    source += "\\hline\n"
    if !body_rows.empty?
      source += body_rows.join(" " + row_break + "\n") + " " + row_break + "\n"
    source += "\\hline\n\\end{tabular}"
    LatexFragment.from_parts(source, all_cells)

  -> .table(headers, rows, caption = nil, label_value = nil, alignment = nil)
    source = "\\begin{table}\n\\centering\n"
    tabular_fragment = tabular(headers, rows, alignment)
    parts = [tabular_fragment]
    source += tabular_fragment.source
    source += "\n\\caption{" + escape(caption) + "}" if caption != nil
    if label_value != nil
      label_fragment = label(label_value)
      parts.push(label_fragment)
      source += "\n" + label_fragment.source
    source += "\n\\end{table}"
    LatexFragment.from_parts(source, parts)

  -> .paragraph(value)
    raw(escape(value) + "\n\n")

  -> .section(title, body, label_value = nil)
    source = "\\section{" + escape(title) + "}"
    parts = []
    if label_value != nil
      label_fragment = label(label_value)
      parts.push(label_fragment)
      source += "\n" + label_fragment.source
    body_fragment = body.class_name == "LatexFragment" ? body : raw(escape(body))
    parts.push(body_fragment)
    source += "\n" + body_fragment.source
    LatexFragment.from_parts(source, parts)

  -> .document(body, title = nil, author = nil)
    body_fragment = body.class_name == "LatexFragment" ? body : raw(escape(body))
    source = "\\documentclass{article}\n\\usepackage{amsmath}\n\\usepackage{amssymb}\n"
    source += "\\title{" + escape(title) + "}\n" if title != nil
    source += "\\author{" + escape(author) + "}\n" if author != nil
    source += "\\begin{document}\n"
    source += "\\maketitle\n" if title != nil || author != nil
    source += body_fragment.source + "\n\\end{document}"
    LatexFragment.from_parts(source, [body_fragment])


# Immutable trusted TeX source. Construct through LaTeX helpers so the raw
# boundary stays visible at call sites.
+ LatexFragment
  ro :source, :reference_chain

  -> new(source, reference_events = nil)
    @source = source
    if reference_events == nil
      @reference_chain = LatexEventChain.leaf([])
    elsif reference_events.class_name == "LatexEventChain"
      @reference_chain = reference_events
    else
      if reference_events.class_name != "Array"
        raise "LatexFragment reference events must be an Array"
      @reference_chain = LatexEventChain.leaf(reference_events)

  -> .from_parts(source, parts)
    raise "LatexFragment parts must be an Array" if parts.class_name != "Array"
    chains = []
    parts.each -> (part)
      if part.class_name != "LatexFragment"
        raise "LatexFragment parts must contain fragments"
      chains.push(part.reference_chain)
    LatexFragment.new(source, LatexEventChain.combine(chains))

  -> reference_events
    @reference_chain.flatten

  -> +(other)
    fragment = LaTeX.coerce(other)
    LatexFragment.from_parts(@source + fragment.source, [self, fragment])

  -> append(other)
    self + other

  -> empty?
    @source.empty?

  -> to_s
    @source

  -> inspect
    @source


# Small append-only builder for sections assembled over several statements.
+ LatexBuilder
  -> new
    @parts = []

  -> append(value)
    @parts.push(LaTeX.coerce(value))
    self

  -> text(value)
    @parts.push(LaTeX.text(value))
    self

  -> math(value)
    @parts.push(LaTeX.inline(value))
    self

  -> line(value)
    @parts.push(LaTeX.coerce(value))
    @parts.push(LaTeX.raw("\n"))
    self

  -> equation(value, label_value = nil)
    line(LaTeX.equation(value, label_value))

  -> section(title, body, label_value = nil)
    line(LaTeX.section(title, body, label_value))

  -> to_fragment
    LaTeX.concat(@parts)

  -> to_s
    to_fragment.source

  -> inspect
    to_s
