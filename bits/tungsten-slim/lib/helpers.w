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

  # Escape HTML special characters in a string
  -> .escape_html(text)
    return "" if text.nil?
    out = text.to_s.gsub("&", "&amp;")
    out = out.gsub("<", "&lt;")
    out = out.gsub(">", "&gt;")
    out = out.gsub("\"", "&quot;")
    out.gsub("'", "&#39;")

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
        =>      parts.push("[key]=\"[Tungsten:Slim:Helpers.escape_html(value)]\"")

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
    attrs = {}

    # ID from shorthand (#) or attribute
    if element.id
      attrs["id"] = element.id

    # Merge classes from shorthand (.) and explicit class attribute
    if element.classes.any? || element.attributes["class"]
      attrs["class"] = Tungsten:Slim:Helpers.merge_classes(element.classes, element.attributes["class"])

    # Copy remaining attributes (skip class since we handled it)
    element.attributes.each -> (key, value)
      if key != "class"
        attrs[key] = value

    Tungsten:Slim:Helpers.build_attributes(attrs)

  # Generate an indentation string
  -> .indent(level)
    "  " * level
