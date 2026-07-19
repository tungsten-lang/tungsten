# Error formatter — ports implementations/ruby/lib/tungsten/error_reporter.rb
# to Tungsten. Produces Ruby-interpreter-style formatted compile errors
# with ANSI color, source context, and caret underline.
#
# Usage:
#   err = compile_error(code: :E_LEX_UNEXPECTED_CHAR,
#                       message: "Unexpected character '['",
#                       file: @file, row: @line, col: @col)
#   raise err
#
# The top-level driver in compiler/tungsten.w catches :compile_error hashes
# and calls format_compile_error(err) to render them.

# -- ANSI escape constants --

-> ansi_reset
  "\e[0m"

-> ansi_bold
  "\e[1m"

-> ansi_dim
  "\e[2m"

-> ansi_bright_red
  "\e[91m"

# -- Helper constructor --
# Central place to build a structured compile-error hash. Every raise
# site in lexer/parser/lowering should go through this helper so the
# schema is authoritative in one place.

-> compile_error(code, message, file, row, col)
  {
    rt:      :compile_error,
    code:    code,
    message: message,
    file:    file,
    row:     row,
    col:     col,
    span_length: 1
  }

-> compile_error_with_span(code, message, file, row, col, span_length)
  {
    rt:      :compile_error,
    code:    code,
    message: message,
    file:    file,
    row:     row,
    col:     col,
    span_length: span_length
  }

# Build a structured error from an AST node. Pulls row/col from the
# node's `:loc` slab slot and span_length from `:loc_end` (AST task
# #9). Falls back to span_length 1 when end_loc isn't populated or
# the span crosses lines — Node#span_length already handles both.
# Use this in preference to compile_error when the offending site is
# a parsed node so the underline reflects the actual source range.
-> compile_error_for_node(code, message, file, node)
  if node == nil
    return compile_error(code, message, file, nil, nil)
  {
    rt:      :compile_error,
    code:    code,
    message: message,
    file:    file,
    row:     node.line,
    col:     node.col,
    span_length: node.span_length
  }

# -- Color detection --
# ANSI on if stderr is a TTY and NO_COLOR is not set. read_file and
# env are both compile-time-safe builtins.

-> error_formatter_use_color
  # NO_COLOR always wins (https://no-color.org); CLICOLOR_FORCE forces color on
  # even when piped; otherwise colorize only when stdout is a real terminal, so
  # ANSI escapes never leak into pipes, files, or CI logs.
  if env("NO_COLOR") != nil
    return false
  if env("CLICOLOR_FORCE") != nil
    return true
  ccall("w_isatty_stdout") == true

-> c(color_on, code)
  if color_on
    return code
  ""

# -- Path shortening --
# Strip $PWD prefix so paths show as relative to where the user
# invoked the compiler.

-> shorten_path(path)
  if path == nil
    return nil
  cwd = env("PWD")
  if cwd == nil
    return path
  prefix = cwd + "/"
  if path.starts_with?(prefix)
    return path.slice(prefix.size(), path.size() - prefix.size())
  path

# -- Integer right-justification helper --
# Tungsten's Integer#to_s doesn't have .rjust; do it by hand.

-> pad_left(s, width)
  pad = width - s.size()
  if pad <= 0
    return s
  out = StringBuffer(width)
  i = 0
  while i < pad
    out << " "
    i += 1
  out << s
  out.to_s()

# -- Runtime error formatter --
# Runtime errors are raised as plain strings (no source span), so there's no
# caret. When the driver knows the source file, include it without inventing a
# line number; otherwise render just the clean `error: <message>` header.

-> format_runtime_error(message, file = nil)
  color = error_formatter_use_color()
  out = StringBuffer(128)
  out << "\n"
  out << c(color, ansi_bright_red())
  out << "error: "
  out << c(color, ansi_reset())
  out << c(color, ansi_bold())
  out << message.to_s()
  out << c(color, ansi_reset())
  out << "\n"
  if file != nil
    out << "\n"
    out << c(color, ansi_dim())
    out << "  --> "
    out << shorten_path(file)
    out << c(color, ansi_reset())
    out << "\n"
  out.to_s()

# -- Main formatter --
# Takes a :compile_error hash and returns a formatted multi-line string
# ready to print to stderr. The hash must have :message; file/row/col/
# source context are optional. If file is present but unreadable,
# source context is skipped without error.

# Split multi-line messages so `help:` trails render as dim notes.
-> format_error_message_lines(out, color, message)
  text = message.to_s()
  parts = text.split("\n")
  i = 0
  while i < parts.size()
    line = parts[i]
    if i == 0
      out << c(color, ansi_bold())
      out << line
      out << c(color, ansi_reset())
    elsif line.starts_with?("  help:") || line.starts_with?("help:")
      out << "\n"
      out << c(color, ansi_dim())
      out << line
      out << c(color, ansi_reset())
    else
      out << "\n"
      out << line
    i += 1

# Machine-readable compile error for agents/CI.
# Enable with TUNGSTEN_ERROR_FORMAT=json (or --json on the CLI when wired).
-> format_compile_error_json(err)
  code = err[:code]
  if code == nil
    code = "E_UNKNOWN"
  msg = err[:message]
  if msg == nil
    msg = ""
  # Escape for a one-line JSON object (no dependency on full JSON encoder).
  esc = "" + msg.to_s()
  esc = esc.replace("\\", "\\\\")
  esc = esc.replace("\"", "\\\"")
  esc = esc.replace("\n", "\\n")
  esc = esc.replace("\r", "\\r")
  file = err[:file]
  if file == nil
    file = ""
  else
    file = "" + shorten_path(file).to_s()
    file = file.replace("\\", "\\\\")
    file = file.replace("\"", "\\\"")
  row = err[:row]
  col = err[:col]
  span = err[:span_length]
  if span == nil
    span = 1
  row_s = "null"
  if row != nil
    row_s = row.to_s()
  col_s = "null"
  if col != nil
    col_s = col.to_s()
  "{\"rt\":\"compile_error\",\"code\":\"" + code.to_s() + "\",\"message\":\"" + esc + "\",\"file\":\"" + file + "\",\"row\":" + row_s + ",\"col\":" + col_s + ",\"span_length\":" + span.to_s() + "}"

-> error_format_is_json?
  fmt = env("TUNGSTEN_ERROR_FORMAT")
  if fmt == nil
    return false
  fmt = "" + fmt
  fmt == "json" || fmt == "JSON"

-> emit_compile_error(err)
  if error_format_is_json?
    return format_compile_error_json(err)
  format_compile_error(err)

-> format_compile_error(err)
  color = error_formatter_use_color()

  message = err[:message]
  file    = err[:file]
  row     = err[:row]
  col     = err[:col]
  span    = err[:span_length]
  if span == nil
    span = 1

  gutter_width = 0
  if row != nil
    gutter_width = (row + 2).to_s().size()

  out = StringBuffer(256)
  out << "\n"

  # Header: `error: <message>` (optional multi-line help: notes)
  out << c(color, ansi_bright_red())
  out << "error: "
  out << c(color, ansi_reset())
  format_error_message_lines(out, color, message)
  out << "\n"

  # Location arrow: `  --> file:row:col`
  if file != nil
    file_str = shorten_path(file)
    if file_str == nil
      file_str = "(eval)"
    out << "\n"
    out << pad_left("", gutter_width + 1)
    out << c(color, ansi_dim())
    out << "--> "
    out << c(color, ansi_reset())
    out << c(color, ansi_dim())
    out << file_str
    if row != nil
      out << ":"
      out << row.to_s()
      if col != nil
        out << ":"
        out << col.to_s()
    out << c(color, ansi_reset())
    out << "\n"

  # Source context with caret
  source = nil
  if file != nil
    source = read_file(file)

  if source != nil && row != nil
    source_lines = source.split("\n")
    if row >= 1 && row <= source_lines.size()
      actual_col = col
      if actual_col == nil
        actual_col = 1

      # Blank gutter line above the context block
      out << pad_left("", gutter_width + 1)
      out << c(color, ansi_dim())
      out << "|"
      out << c(color, ansi_reset())
      out << "\n"

      # Up to 2 lines of context before the error line
      ctx_start = row - 2
      if ctx_start < 1
        ctx_start = 1
      ctx_i = ctx_start
      while ctx_i <= row - 1
        out << c(color, ansi_dim())
        out << pad_left(ctx_i.to_s(), gutter_width)
        out << " | "
        out << source_lines[ctx_i - 1]
        out << c(color, ansi_reset())
        out << "\n"
        ctx_i += 1

      # The error line itself (undimmed)
      out << c(color, ansi_dim())
      out << pad_left(row.to_s(), gutter_width)
      out << " |"
      out << c(color, ansi_reset())
      out << " "
      out << source_lines[row - 1]
      out << "\n"

      # Caret + underline row
      if actual_col >= 1
        out << pad_left("", gutter_width + 1)
        out << c(color, ansi_dim())
        out << "|"
        out << c(color, ansi_reset())
        out << " "
        pad_i = 1
        while pad_i < actual_col
          out << " "
          pad_i += 1
        out << c(color, ansi_bright_red())
        out << "^"
        underline_i = 1
        while underline_i < span
          out << "~"
          underline_i += 1
        out << c(color, ansi_reset())
        out << "\n"

      # Up to 2 lines of context after the error line, stopping at blank
      after_start = row + 1
      after_end = after_start + 1
      if after_end > source_lines.size()
        after_end = source_lines.size()
      ctx_j = after_start
      while ctx_j <= after_end
        content = source_lines[ctx_j - 1]
        if content == nil || content.strip() == ""
          break
        out << c(color, ansi_dim())
        out << pad_left(ctx_j.to_s(), gutter_width)
        out << " | "
        out << content
        out << c(color, ansi_reset())
        out << "\n"
        ctx_j += 1

  # Footer: point at the error-code lesson registry (doc/explain.md).
  code = err[:code]
  if code != nil
    out << "\n"
    out << c(color, ansi_dim())
    out << "  explain: tungsten --explain "
    out << code.to_s()
    out << c(color, ansi_reset())
    out << "\n"

  out.to_s()

# -- Convenience: format and print to stderr --

-> print_compile_error(err)
  formatted = format_compile_error(err)
  << formatted
  nil
