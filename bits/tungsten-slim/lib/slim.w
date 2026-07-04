# Tungsten Slim — whitespace-significant template engine
# Clean syntax, compiles to HTML. Built for Tungsten.

in Tungsten:Slim

use version
use engine
use parser
use compiler
use node
use helpers

# Render a Slim template string with the given local variables
-> render(source, locals = {})
  engine = Engine.new
  engine.render(source, locals)

# Render a Slim template from a file path
-> render_file(path, locals = {})
  source = File.read(path)
  render(source, locals)

# Parse a Slim template into a node tree (useful for inspection)
-> parse(source)
  parser = Parser.new
  parser.parse(source)
