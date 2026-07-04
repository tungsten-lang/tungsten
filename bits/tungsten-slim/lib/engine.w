# Slim::Engine — template compilation and rendering pipeline
#
# Orchestrates the full lifecycle: parse → compile → output.
# Supports template caching for production performance.

in Tungsten:Slim

+ Engine
  # Template cache — stores compiled templates by source hash
  @@cache = {}
  @@cache_enabled = false

  -> new(cache: false)
    @@cache_enabled = cache

  # Render a Slim template string with optional local variables
  -> render(source, locals = {})
    root = parse(source)
    compile(root, locals)

  # Render a template file with local variables
  -> render_file(path, locals = {})
    if @@cache_enabled && @@cache[path]
      root = @@cache[path]
    else
      source = File.read(path)
      root = parse(source)
      @@cache[path] = root if @@cache_enabled
    render_from_tree(root, locals)

  # Parse source into an AST
  -> parse(source)
    parser = Parser.new
    parser.parse(source)

  # Compile an AST into HTML output
  -> compile(root, locals = {})
    compiler = Compiler.new
    compiler.compile(root, locals)

  # Render from a pre-parsed tree (used by caching)
  -> render_from_tree(root, locals = {})
    compiler = Compiler.new
    compiler.compile(root, locals)

  # Clear the template cache
  -> .clear_cache
    @@cache = {}

  # Enable or disable caching globally
  -> .cache=(enabled)
    @@cache_enabled = enabled

  # Register Slim as a template handler with Carbide
  -> .register!
    if defined?(Tungsten:Carbide)
      Carbide:View.register_handler(:slim, SlimHandler.new)


# Handler that integrates with Carbide's view system
+ SlimHandler
  -> new
    @engine = Engine.new

  -> render(source, locals = {})
    @engine.render(source, locals)

  -> file_extensions
    ["slim"]
