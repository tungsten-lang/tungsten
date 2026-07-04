# Tungsten LSP — MCP Server
#
# Wraps the Tungsten language analysis as an MCP server so Claude Code
# can use go-to-definition, hover, find-references, etc. on .w files.
#
# Run with: tungsten bits/tungsten-lsp/bin/mcp-server.w

use json
use ../../../compiler/lib/ast
use ../../../compiler/lib/lexer
use ../../../compiler/lib/parser
use ../lib/analyze

# -- MCP I/O --

-> mcp_read_message
  content_length = 0
  line = gets
  while line != nil && line != "" && line != "\r"
    if line.starts_with?("Content-Length:")
      content_length = line.slice(16, line.size - 16).strip.to_i
    line = gets

  return nil if content_length == 0

  body = read_bytes(content_length)
  JSON.parse(body)

-> mcp_send(msg)
  body = JSON.encode(msg)
  print("Content-Length: " + body.size.to_s + "\r\n\r\n" + body)
  flush

-> mcp_respond(id, result)
  mcp_send({"jsonrpc": "2.0", "id": id, "result": result})

-> mcp_error(id, code, message)
  mcp_send({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})

# -- Tool definitions --

-> tool_definitions
  [
    {
      "name": "tungsten_symbols",
      "description": "List all definitions (methods, classes, traits, modules) in a Tungsten .w file",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string", "description": "Path to the .w file"}
        },
        "required": ["file"]
      }
    },
    {
      "name": "tungsten_hover",
      "description": "Get the signature/type info for a symbol at a position in a Tungsten .w file",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string", "description": "Path to the .w file"},
          "line": {"type": "integer", "description": "Line number (0-based)"},
          "character": {"type": "integer", "description": "Column (0-based)"}
        },
        "required": ["file", "line", "character"]
      }
    },
    {
      "name": "tungsten_definition",
      "description": "Find where a symbol is defined in a Tungsten .w file (supports cross-file lookup via use-paths)",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string", "description": "Path to the .w file"},
          "line": {"type": "integer", "description": "Line number (0-based)"},
          "character": {"type": "integer", "description": "Column (0-based)"}
        },
        "required": ["file", "line", "character"]
      }
    },
    {
      "name": "tungsten_references",
      "description": "Find all references to the symbol at a position in a Tungsten .w file",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string", "description": "Path to the .w file"},
          "line": {"type": "integer", "description": "Line number (0-based)"},
          "character": {"type": "integer", "description": "Column (0-based)"}
        },
        "required": ["file", "line", "character"]
      }
    },
    {
      "name": "tungsten_signature",
      "description": "Get the parameter signature of a function/method at a position in a Tungsten .w file",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string", "description": "Path to the .w file"},
          "line": {"type": "integer", "description": "Line number (0-based)"},
          "character": {"type": "integer", "description": "Column (0-based)"}
        },
        "required": ["file", "line", "character"]
      }
    },
    {
      "name": "tungsten_workspace_symbols",
      "description": "Search for symbols across all indexed Tungsten .w files in the project",
      "inputSchema": {
        "type": "object",
        "properties": {
          "query": {"type": "string", "description": "Search query (empty string for all symbols)"}
        },
        "required": ["query"]
      }
    },
    {
      "name": "tungsten_completions",
      "description": "Get completion suggestions at a position in a Tungsten .w file",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string", "description": "Path to the .w file"},
          "line": {"type": "integer", "description": "Line number (0-based)"},
          "character": {"type": "integer", "description": "Column (0-based)"}
        },
        "required": ["file", "line", "character"]
      }
    }
  ]

# -- Tool handlers --

-> read_and_index(file)
  return nil unless file?(file)
  text = read_file(file)
  index_file(file, text)
  index_dependencies(text, file)
  text

-> handle_tool(name, args)
  if name == "tungsten_symbols"
    file = args["file"]
    text = read_and_index(file)
    return {"content": [{"type": "text", "text": "File not found: " + file}], "isError": true} if text == nil

    symbols = extract_symbols(text)
    lines = []
    symbols ->(sym)
      lines.push(sym["name"] + " (" + sym["kind"].to_s + ") line " + sym["range"]["start"]["line"].to_s)
    return {"content": [{"type": "text", "text": lines.join("\n")}]}

  if name == "tungsten_hover"
    file = args["file"]
    text = read_and_index(file)
    return {"content": [{"type": "text", "text": "File not found"}], "isError": true} if text == nil

    uri = "file://" + file
    info = hover_info(text, args["line"], args["character"], uri)
    return {"content": [{"type": "text", "text": info || "No hover info"}]}

  if name == "tungsten_definition"
    file = args["file"]
    text = read_and_index(file)
    return {"content": [{"type": "text", "text": "File not found"}], "isError": true} if text == nil

    uri = "file://" + file
    loc = find_definition(text, args["line"], args["character"], uri)
    if loc == nil
      return {"content": [{"type": "text", "text": "Definition not found"}]}

    def_file = loc["uri"]
    def_file = def_file.slice(7, def_file.size - 7) if def_file.starts_with?("file://")
    return {"content": [{"type": "text", "text": def_file + ":" + (loc["line"] + 1).to_s}]}

  if name == "tungsten_references"
    file = args["file"]
    text = read_and_index(file)
    return {"content": [{"type": "text", "text": "File not found"}], "isError": true} if text == nil

    uri = "file://" + file
    refs = find_references(text, args["line"], args["character"], uri)
    lines = []
    refs ->(ref)
      lines.push(file + ":" + (ref["line"] + 1).to_s + ":" + (ref["col"] + 1).to_s)
    return {"content": [{"type": "text", "text": lines.join("\n")}]}

  if name == "tungsten_signature"
    file = args["file"]
    text = read_and_index(file)
    return {"content": [{"type": "text", "text": "File not found"}], "isError": true} if text == nil

    uri = "file://" + file
    help = signature_help(text, args["line"], args["character"], uri)
    if help == nil
      return {"content": [{"type": "text", "text": "No signature info"}]}
    sig = help["signatures"][0]
    return {"content": [{"type": "text", "text": sig["label"]}]}

  if name == "tungsten_workspace_symbols"
    results = workspace_symbols(args["query"])
    lines = []
    results ->(sym)
      loc = sym["location"]
      path = loc["uri"]
      path = path.slice(7, path.size - 7) if path.starts_with?("file://")
      lines.push(sym["name"] + " — " + path + ":" + (loc["range"]["start"]["line"] + 1).to_s)
    return {"content": [{"type": "text", "text": lines.join("\n")}]}

  if name == "tungsten_completions"
    file = args["file"]
    text = read_and_index(file)
    return {"content": [{"type": "text", "text": "File not found"}], "isError": true} if text == nil

    uri = "file://" + file
    items = complete(text, args["line"], args["character"], uri)
    lines = []
    items ->(item)
      detail = item["detail"]
      if detail != nil
        lines.push(item["label"] + detail)
      else
        lines.push(item["label"])
    return {"content": [{"type": "text", "text": lines.join("\n")}]}

  {"content": [{"type": "text", "text": "Unknown tool: " + name}], "isError": true}

# -- Main loop --

-> run_mcp_server
  log("tungsten-mcp starting")
  running = true

  while running
    msg = mcp_read_message
    if msg == nil
      running = false
      next

    method = msg["method"]
    id = msg["id"]

    if method == "initialize"
      mcp_respond(id, {
        "protocolVersion": "2024-11-05",
        "capabilities": {
          "tools": {}
        },
        "serverInfo": {
          "name": "tungsten-lsp",
          "version": "0.2.0"
        }
      })
    elsif method == "notifications/initialized"
      log("tungsten-mcp initialized")
    elsif method == "tools/list"
      mcp_respond(id, {"tools": tool_definitions})
    elsif method == "tools/call"
      name = msg["params"]["name"]
      args = msg["params"]["arguments"]
      result = handle_tool(name, args)
      mcp_respond(id, result)
    elsif id != nil
      mcp_error(id, -32601, "Method not found: " + method.to_s)

  log("tungsten-mcp exiting")

run_mcp_server
