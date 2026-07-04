in Tungsten:Emberclaw

trait Readable
  -> read(path, offset=nil, limit=nil)
    # Simulated read
    "Simulated content from [path] (offset: [offset], limit: [limit])"

trait Writable
  -> write(path, content)
    # Simulated write
    << "Simulated write to [path]: [content]"

trait Editable
  -> edit(path, edits)
    # Simulated edit
    << "Simulated edits to [path]: [edits]"

trait Executable
  -> exec(command, options={})
    # Simulated exec
    "Simulated output of [command] with options [options]"
