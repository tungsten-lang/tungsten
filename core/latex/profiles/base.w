# Shared, data-oriented publication profile support.

+ LatexProfile
  -> new(name, document_class, class_options, packages,
         bibliography_style, metadata_style, extra_preamble = nil)
    initialize_profile(
      name, document_class, class_options, packages,
      bibliography_style, metadata_style, extra_preamble)

  -> initialize_profile(name, document_class, class_options, packages,
                        bibliography_style, metadata_style,
                        extra_preamble = nil)
    @name = name
    @document_class = document_class
    @class_options = class_options
    @packages = packages
    @bibliography_style = bibliography_style
    @metadata_style = metadata_style
    @extra_preamble = extra_preamble == nil ? [] : extra_preamble
    self

  -> name
    @name

  -> document_class
    @document_class

  -> class_options
    @class_options

  -> packages
    @packages

  -> bibliography_style
    @bibliography_style

  -> safe_option?(value)
    text = value.to_s
    return false if text.empty?
    bytes = text.bytes
    i = 0
    while i < bytes.size
      byte = bytes[i]
      safe = LaTeX.ascii_letter?(byte) || LaTeX.ascii_digit?(byte)
      safe = safe || byte == 44 || byte == 45 || byte == 46
      safe = safe || byte == 58 || byte == 61 || byte == 95
      return false if !safe
      i += 1
    true

  -> validate_option(value)
    text = value.to_s
    raise "unsafe LaTeX profile option: " + text if !safe_option?(text)
    text

  -> validate_package(value)
    text = value.to_s
    if !LaTeX.safe_control_name?(text)
      raise "unsafe LaTeX package name: " + text
    text

  -> metadata_value(metadata, key)
    return nil if metadata == nil || !metadata.has_key?(key)
    metadata[key]

  -> metadata_source(value)
    return "" if value == nil
    return value.source if value.class_name == "LatexFragment"
    LaTeX.escape(value)

  -> authors_source(value, separator)
    return "" if value == nil
    return metadata_source(value) if value.class_name != "Array"
    authors = []
    value.each -> (author)
      authors.push(metadata_source(author))
    authors.join(separator)

  -> keywords_source(value)
    return "" if value == nil
    return metadata_source(value) if value.class_name != "Array"
    keywords = []
    value.each -> (keyword)
      keywords.push(metadata_source(keyword))
    keywords.join(", ")

  -> document_class_fragment
    class_name = validate_package(@document_class)
    if @class_options.empty?
      return LaTeX.raw("\\documentclass{" + class_name + "}")
    options = []
    @class_options.each -> (option)
      options.push(validate_option(option))
    LaTeX.raw("\\documentclass\[" + options.join(",") + "]{" + class_name + "}")

  -> package_fragment(package)
    package_name = package
    options = nil
    if package.class_name == "Array"
      raise "LaTeX profile package entries need name and options" if package.size != 2
      package_name = package[0]
      options = package[1]
    package_name = validate_package(package_name)
    if options == nil
      return LaTeX.raw("\\usepackage{" + package_name + "}")
    LaTeX.raw("\\usepackage\[" + validate_option(options) + "]{" + package_name + "}")

  -> preamble_fragment(metadata = nil)
    parts = [document_class_fragment]
    @packages.each -> (package)
      parts.push(package_fragment(package))
    @extra_preamble.each -> (line)
      parts.push(LaTeX.raw(line))
    metadata_part = metadata_preamble(metadata)
    parts.push(metadata_part) if !metadata_part.empty?
    LaTeX.join(parts, LaTeX.raw("\n"))

  -> metadata_preamble(metadata)
    return LaTeX.raw("") if @metadata_style == :thesis
    parts = []
    title = metadata_value(metadata, :title)
    authors = metadata_value(metadata, :authors)
    authors = metadata_value(metadata, :author) if authors == nil
    date = metadata_value(metadata, :date)
    parts.push(LaTeX.raw("\\title{" + metadata_source(title) + "}")) if title != nil
    if authors != nil && @metadata_style == :acm && authors.class_name == "Array"
      authors.each -> (author)
        parts.push(LaTeX.raw("\\author{" + metadata_source(author) + "}"))
    elsif authors != nil
      parts.push(LaTeX.raw("\\author{" + authors_source(authors, " \\and ") + "}"))
    parts.push(LaTeX.raw("\\date{" + metadata_source(date) + "}")) if date != nil
    LaTeX.join(parts, LaTeX.raw("\n"))

  -> abstract_fragment(metadata)
    abstract_value = metadata_value(metadata, :abstract)
    return LaTeX.raw("") if abstract_value == nil
    LaTeX.environment("abstract", LaTeX.raw(metadata_source(abstract_value)))

  -> keywords_fragment(metadata)
    keywords = metadata_value(metadata, :keywords)
    return LaTeX.raw("") if keywords == nil
    if @metadata_style == :ieee
      return LaTeX.environment("IEEEkeywords", LaTeX.raw(keywords_source(keywords)))
    if @metadata_style == :acm
      return LaTeX.raw("\\keywords{" + keywords_source(keywords) + "}")
    LaTeX.raw("\\paragraph{Keywords} " + keywords_source(keywords))

  -> opening_fragment(metadata)
    return thesis_opening_fragment(metadata) if @metadata_style == :thesis
    parts = []
    title = metadata_value(metadata, :title)
    authors = metadata_value(metadata, :authors)
    authors = metadata_value(metadata, :author) if authors == nil
    parts.push(LaTeX.raw("\\maketitle")) if title != nil || authors != nil
    abstract_part = abstract_fragment(metadata)
    parts.push(abstract_part) if !abstract_part.empty?
    keyword_part = keywords_fragment(metadata)
    parts.push(keyword_part) if !keyword_part.empty?
    LaTeX.join(parts, LaTeX.raw("\n"))

  -> thesis_opening_fragment(metadata)
    title = metadata_value(metadata, :title)
    authors = metadata_value(metadata, :authors)
    authors = metadata_value(metadata, :author) if authors == nil
    institution = metadata_value(metadata, :institution)
    degree = metadata_value(metadata, :degree)
    date = metadata_value(metadata, :date)
    lines = ["\\begin{titlepage}", "\\centering"]
    lines.push("{\\LARGE " + metadata_source(title) + "\\par}") if title != nil
    lines.push("\\vfill")
    lines.push("{\\large " + authors_source(authors, ", ") + "\\par}") if authors != nil
    lines.push(metadata_source(degree) + "\\par") if degree != nil
    lines.push(metadata_source(institution) + "\\par") if institution != nil
    lines.push("\\vfill")
    lines.push(metadata_source(date) + "\\par") if date != nil
    lines.push("\\end{titlepage}")
    abstract_part = abstract_fragment(metadata)
    lines.push(abstract_part.source) if !abstract_part.empty?
    keyword_part = keywords_fragment(metadata)
    lines.push(keyword_part.source) if !keyword_part.empty?
    LaTeX.raw(lines.join("\n"))

  -> bibliography_fragment(metadata)
    resource = metadata_value(metadata, :bibliography)
    return LaTeX.raw("") if resource == nil
    resource_name = LaTeX.validated_label(resource)
    style = metadata_value(metadata, :bibliography_style)
    style = @bibliography_style if style == nil
    style_name = LaTeX.validated_label(style)
    source = "\\bibliographystyle{" + style_name + "}\n"
    LaTeX.raw(source + "\\bibliography{" + resource_name + "}")

  -> document(body, metadata = nil)
    metadata = {} if metadata == nil
    body_source = body.class_name == "LatexFragment" ? body.source : LaTeX.escape(body)
    parts = [preamble_fragment(metadata), LaTeX.raw("\\begin{document}")]
    opening = opening_fragment(metadata)
    parts.push(opening) if !opening.empty?
    parts.push(LaTeX.raw(body_source))
    bibliography = bibliography_fragment(metadata)
    parts.push(bibliography) if !bibliography.empty?
    parts.push(LaTeX.raw("\\end{document}"))
    LaTeX.join(parts, LaTeX.raw("\n"))

  -> to_s
    @name.to_s

  -> inspect
    "LatexProfile(" + @name.to_s + ")"
