# Inspectable trait
#
# Include in classes that render a developer-facing representation via
# inspect. The default falls back to the printable form; conformers (and
# native inline-cache rows) override it with a richer rendering.
trait Inspectable
  -> inspect
    to_s
