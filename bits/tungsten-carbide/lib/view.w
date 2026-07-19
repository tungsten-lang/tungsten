# Carbide::View — template rendering engine
# Supports layouts, partials, and local variable binding.
# Handles both .w.html (embedded Tungsten) and .slim (Slim) templates.

in Tungsten:Carbide

+ View
  ro :template_name
  ro :layout
  ro :locals

  # Template cache — compiled templates stored by path
  @@cache = {}

  # Registered template handlers by extension
  @@handlers = {}

  -> new(@template_name, layout: "application", locals: {})
    @layout = layout
    @locals = locals

  # Register a template handler for a given file extension
  -> .register_handler(extension, handler)
    @@handlers[extension.to_s] = handler

  # Look up a handler by extension
  -> .handler_for(extension)
    @@handlers[extension.to_s]

  -> render
    content = render_template(@template_name)

    if @layout
      render_layout(@layout, content)
    else
      content

  -> render_template(name)
    path = resolve_template_path(name)
    template = load_template(path)
    template.render(@locals)

  -> render_layout(name, content)
    path = resolve_layout_path(name)
    template = load_template(path)
    template.render(@locals.merge(yield_content: content))

  -> render_partial(name, locals: {})
    # Partials are prefixed with underscore
    parts = name.to_s.split("/")
    parts[-1] = "_#{parts[-1]}"
    path = resolve_template_path(parts.join("/"))
    template = load_template(path)
    template.render(@locals.merge(locals))

  -> render_collection(partial:, collection:, as: nil)
    item_name = as || partial.to_s.split("/").last.to_sym
    collection.map -> (item)
      render_partial(partial, locals: {item_name => item})
    |> self.join("")

  -> resolve_template_path(name)
    # Try .slim first, then fall back to .w.html
    slim_path = "app/views/[name].slim"
    html_path = "app/views/[name].w.html"

    if File.exist?(slim_path)
      slim_path
    else
      html_path

  -> resolve_layout_path(name)
    slim_path = "app/views/layouts/[name].slim"
    html_path = "app/views/layouts/[name].w.html"

    if File.exist?(slim_path)
      slim_path
    else
      html_path

  -> load_template(path)
    if Carbide.app.config.cache_classes && @@cache[path]
      @@cache[path]
    else
      source = File.read(path)
      compiled = compile_for_path(path, source)
      @@cache[path] = compiled
      compiled

  -> compile_for_path(path, source)
    extension = File.extname(path).sub(".", "")

    case extension
      "slim" =>
        # Use Slim engine if available
        handler = @@handlers["slim"]
        if handler
          handler
        else
          # Lazy-load Slim support
          use slim
          engine = Slim:Engine.new
          @@handlers["slim"] = engine
          engine

      =>
        # Default: compile as .w.html template
        Tungsten:Carbide:Template:Compiler.compile(source)


# Compiled template — evaluates embedded Tungsten expressions
+ Template:Compiled
  ro :parts

  -> new(@parts)

  -> render(locals = {})
    @parts.map -> (part)
      case part
        {type: :text, value: v}       => v
        {type: :expression, code: c}  => eval_in_context(c, locals).to_s
        {type: :block, code: c}       => eval_in_context(c, locals); ""
    |> self.join("")

  -> eval_in_context(code, locals)
    # Bind locals as variables and evaluate the expression
    Evaluator.eval(code, locals)


# Template compiler — parses .w.html templates into parts
+ Template:Compiler
  -> .compile(source)
    parts = []
    scanner = StringScanner.new(source)

    while !scanner.eos?
      case
        scanner.scan_until(/\{\{=/) =>
          parts.push({type: :text, value: scanner.pre_match}) if scanner.pre_match
          expr = scanner.scan_until(/\}\}/).chomp("}}")
          parts.push({type: :expression, code: expr.strip})

        scanner.scan_until(/\{\{/) =>
          parts.push({type: :text, value: scanner.pre_match}) if scanner.pre_match
          expr = scanner.scan_until(/\}\}/).chomp("}}")
          parts.push({type: :block, code: expr.strip})

        =>
          parts.push({type: :text, value: scanner.rest})
          scanner.terminate

    Tungsten:Carbide:Template:Compiled.new(parts)
