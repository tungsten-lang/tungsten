# Slim::Helpers — HTML escaping, attribute merging, and output utilities

in Tungsten:Slim

+ Helpers
  # Characters that must be escaped in HTML content
  ESCAPE_MAP = {
    "&"  => "&amp;",
    "<"  => "&lt;",
    ">"  => "&gt;",
    "\"" => "&quot;",
    "'"  => "&#39;"
  }

  INDENT_CACHE = [
    "",
    "  ",
    "    ",
    "      ",
    "        ",
    "          ",
    "            ",
    "              ",
    "                "
  ]

  # Escape HTML special characters in a string
  -> .escape_html(text)
    return "" if text == nil
    s = text.to_s
    n = s.size
    has_amp = false
    has_lt = false
    has_gt = false
    has_quot = false
    has_apos = false
    i = 0
    while i < n
      b = s.byte_at(i)
      if b == 38
        has_amp = true
      elsif b == 60
        has_lt = true
      elsif b == 62
        has_gt = true
      elsif b == 34
        has_quot = true
      elsif b == 39
        has_apos = true
      i = i + 1
    if !has_amp && !has_lt && !has_gt && !has_quot && !has_apos
      return s
    out = s
    out = out.gsub("&", "&amp;") if has_amp
    out = out.gsub("<", "&lt;") if has_lt
    out = out.gsub(">", "&gt;") if has_gt
    out = out.gsub("\"", "&quot;") if has_quot
    out = out.gsub("'", "&#39;") if has_apos
    out

  # Check if a value is "truthy" for attribute rendering
  # false and nil suppress the attribute entirely
  -> .truthy?(value)
    value != false && value != nil

  # Build an HTML attribute string from a hash
  # Boolean attributes (e.g. required, disabled) render without a value
  # nil/false attributes are omitted
  -> .build_attributes(attrs)
    parts = []

    attrs.each -> (key, value)
      case value
        true  => parts.push(key.to_s)
        false => nil  # skip
        nil   => nil  # skip
        =>      parts.push(key.to_s + "=\"" + Tungsten:Slim:Helpers.escape_html(value) + "\"")

    parts.join(" ")

  # Merge class lists — combines explicit class attribute with shorthand classes
  -> .merge_classes(shorthand_classes, attr_classes)
    out = shorthand_classes.join(" ")
    if attr_classes
      extra = attr_classes
      extra = attr_classes.join(" ") if type(attr_classes) == "Array"
      out = out + " " if out.size > 0 && extra.to_s.size > 0
      out = out + extra.to_s
    out

  # Build the full opening tag attributes string from an Element node
  -> .element_attributes(element)
    eid = element.id
    eclasses = element.classes
    eattrs = element.attributes
    if eid == nil && eclasses.empty? && eattrs.empty?
      return ""

    out = ""

    # ID from shorthand (#) or attribute
    if eid
      out = "id=\"" + Tungsten:Slim:Helpers.escape_html(eid) + "\""

    # Merge classes from shorthand (.) and explicit class attribute
    attr_class = eattrs.empty? ? nil : eattrs["class"]
    if !eclasses.empty? || attr_class
      merged = Tungsten:Slim:Helpers.merge_classes(eclasses, attr_class)
      part = "class=\"" + Tungsten:Slim:Helpers.escape_html(merged) + "\""
      out = out.empty? ? part : (out + " " + part)

    # Copy remaining attributes (skip class since we handled it, and id if shorthand id was set)
    if !eattrs.empty?
      eattrs.each -> (key, value)
        if key != "class" && (eid == nil || key != "id")
          if value == true
            part = key.to_s
            out = out.empty? ? part : (out + " " + part)
          elsif value != false && value != nil
            part = key.to_s + "=\"" + Tungsten:Slim:Helpers.escape_html(value) + "\""
            out = out.empty? ? part : (out + " " + part)

    out

  # Generate an indentation string
  -> .indent(level)
    if level >= 0 && level <= 8
      return INDENT_CACHE[level]
    "  " * level
