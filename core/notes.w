# Structured Notes export. Import explicitly; opening a document never runs W.
use json

+ Notes
  -> .text(value)
    {kind: "text", text: value.to_s()}

  -> .table(columns, rows)
    names = columns.map -> item.to_s()
    cells = []
    i = 0
    while i < rows.size()
      cells.push(rows[i].map -> item.to_s())
      i += 1
    {kind: "table", columns: names, rows: cells}

  -> .line_plot(points)
    {kind: "line_plot", points: points}

  # Explicitly export a user object. Its method executes in the producer
  # process, never when the saved document is opened by Notes.
  -> .render(value)
    if value.respond_to?("to_notes")
      return value.to_notes()
    Notes.text(value)

  -> .document(title, blocks)
    {schema_version: 1, title: title, blocks: blocks}

  -> .write(path, title, blocks)
    if !write_file(path, JSON.encode(Notes.document(title, blocks)))
      raise "could not write Notes document"
    path
