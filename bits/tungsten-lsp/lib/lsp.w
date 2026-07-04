# Tungsten Language Server
#
# Implements LSP over stdio (JSON-RPC 2.0).
# Built to bin/lsp by `bin/tungsten build`; that binary is the LSP server.

use json
use ../../../compiler/lib/ast
use ../../../compiler/lib/lexer
use ../../../compiler/lib/parser
use analyze

# -- LSP I/O --

-> lsp_read_message
  # Read the LSP header block via w_read_line_stdin (a getline-backed primitive
  # that works on piped stdin); compiled `gets` returns nil here. Lines keep
  # their trailing `\r` (getline strips only `\n`), so the blank separator
  # reads as "\r". The body is then read as exactly Content-Length bytes —
  # frames are concatenated, so a line read would over-run into the next header.
  content_length = 0
  line = ccall("w_read_line_stdin")
  while line != nil && line != "" && line != "\r"
    if line.starts_with?("Content-Length:")
      content_length = line.slice(16, line.size - 16).strip.to_i
    line = ccall("w_read_line_stdin")

  return nil if content_length == 0

  body = read_bytes(content_length)
  JSON.parse(body)

-> lsp_send(msg)
  body = JSON.encode(msg)
  print("Content-Length: " + body.size.to_s + "\r\n\r\n" + body)
  flush

-> lsp_respond(id, result)
  lsp_send({"jsonrpc": "2.0", "id": id, "result": result})

-> lsp_error(id, code, message)
  lsp_send({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})

-> lsp_notify(method, params)
  lsp_send({"jsonrpc": "2.0", "method": method, "params": params})

# Diagnostics/logging MUST go to stderr — stdout is the JSON-RPC channel.
# (The bare global `log`/`warn` are unimplemented compiled, and `<!` is the
# raise operator; w_eputs is the stderr counterpart of w_puts.)
-> lsp_log(msg)
  ccall("w_eputs", msg)

# -- Document store --

documents = {}

-> doc_open(uri, text)
  documents[uri] = text
  index_from_uri(uri, text)
  path = uri_to_path(uri)
  index_dependencies(text, path) if path != nil
  publish_diagnostics(uri, text)

-> doc_change(uri, text)
  documents[uri] = text
  index_from_uri(uri, text)
  publish_diagnostics(uri, text)

-> doc_close(uri)
  documents.delete(uri)
  # Clear diagnostics for a closed file (LSP: publish an empty list).
  lsp_notify("textDocument/publishDiagnostics", {"uri": uri, "diagnostics": []})

# Push parse/compile diagnostics for a buffer (LSP textDocument/publishDiagnostics).
-> publish_diagnostics(uri, text)
  lsp_notify("textDocument/publishDiagnostics", {"uri": uri, "diagnostics": diagnose(text, uri)})

-> doc_text(uri)
  return documents[uri] if documents.has_key?(uri)
  path = uri_to_path(uri)
  if path != nil && file?(path)
    return read_file(path)
  nil

# -- Request handlers --

-> handle_initialize(id, params)
  lsp_respond(id, {
    "capabilities": {
      "textDocumentSync": 1,
      "documentSymbolProvider": true,
      "hoverProvider": true,
      "definitionProvider": true,
      "referencesProvider": true,
      "completionProvider": {"triggerCharacters": [".", ":"]},
      "signatureHelpProvider": {"triggerCharacters": ["(", ","]},
      "workspaceSymbolProvider": true
    },
    "serverInfo": {
      "name": "tungsten-lsp",
      "version": "0.2.0"
    }
  })

-> handle_document_symbols(id, params)
  uri = params["textDocument"]["uri"]
  text = doc_text(uri)
  return lsp_respond(id, []) if text == nil

  lsp_respond(id, extract_symbols(text))

-> handle_hover(id, params)
  uri = params["textDocument"]["uri"]
  text = doc_text(uri)
  return lsp_respond(id, nil) if text == nil

  line = params["position"]["line"]
  col = params["position"]["character"]
  info = hover_info(text, line, col, uri)
  return lsp_respond(id, nil) if info == nil

  lsp_respond(id, {"contents": {"kind": "markdown", "value": info}})

-> handle_definition(id, params)
  uri = params["textDocument"]["uri"]
  text = doc_text(uri)
  return lsp_respond(id, nil) if text == nil

  line = params["position"]["line"]
  col = params["position"]["character"]
  loc = find_definition(text, line, col, uri)
  return lsp_respond(id, nil) if loc == nil

  lsp_respond(id, {
    "uri": loc["uri"],
    "range": {
      "start": {"line": loc["line"], "character": loc["col"]},
      "end": {"line": loc["line"], "character": loc["end_col"]}
    }
  })

-> handle_references(id, params)
  uri = params["textDocument"]["uri"]
  text = doc_text(uri)
  return lsp_respond(id, []) if text == nil

  line = params["position"]["line"]
  col = params["position"]["character"]
  refs = find_references(text, line, col, uri)

  locations = []
  refs ->(ref)
    locations.push({
      "uri": ref["uri"],
      "range": {
        "start": {"line": ref["line"], "character": ref["col"]},
        "end": {"line": ref["line"], "character": ref["end_col"]}
      }
    })
  lsp_respond(id, locations)

-> handle_completion(id, params)
  uri = params["textDocument"]["uri"]
  text = doc_text(uri)
  return lsp_respond(id, []) if text == nil

  line = params["position"]["line"]
  col = params["position"]["character"]
  items = complete(text, line, col, uri)
  lsp_respond(id, items)

-> handle_signature_help(id, params)
  uri = params["textDocument"]["uri"]
  text = doc_text(uri)
  return lsp_respond(id, nil) if text == nil

  line = params["position"]["line"]
  col = params["position"]["character"]
  help = signature_help(text, line, col, uri)
  return lsp_respond(id, nil) if help == nil

  lsp_respond(id, help)

-> handle_workspace_symbols(id, params)
  query = params["query"]
  query = "" if query == nil
  lsp_respond(id, workspace_symbols(query))

# -- Main loop --

-> run_server
  lsp_log("tungsten-lsp v0.2.0 starting")
  running = true

  while running
    msg = lsp_read_message
    if msg == nil
      running = false
      next

    method = msg["method"]
    id = msg["id"]

    if method == "initialize"
      handle_initialize(id, msg["params"])
    elsif method == "initialized"
      lsp_log("tungsten-lsp initialized")
    elsif method == "shutdown"
      lsp_respond(id, nil)
    elsif method == "exit"
      running = false
    elsif method == "textDocument/didOpen"
      td = msg["params"]["textDocument"]
      doc_open(td["uri"], td["text"])
    elsif method == "textDocument/didChange"
      uri = msg["params"]["textDocument"]["uri"]
      changes = msg["params"]["contentChanges"]
      if changes.size > 0
        doc_change(uri, changes[changes.size - 1]["text"])
    elsif method == "textDocument/didClose"
      doc_close(msg["params"]["textDocument"]["uri"])
    elsif method == "textDocument/documentSymbol"
      handle_document_symbols(id, msg["params"])
    elsif method == "textDocument/hover"
      handle_hover(id, msg["params"])
    elsif method == "textDocument/definition"
      handle_definition(id, msg["params"])
    elsif method == "textDocument/references"
      handle_references(id, msg["params"])
    elsif method == "textDocument/completion"
      handle_completion(id, msg["params"])
    elsif method == "textDocument/signatureHelp"
      handle_signature_help(id, msg["params"])
    elsif method == "workspace/symbol"
      handle_workspace_symbols(id, msg["params"])
    elsif id != nil
      lsp_error(id, -32601, "Method not found: " + method.to_s)

  lsp_log("tungsten-lsp exiting")

run_server
