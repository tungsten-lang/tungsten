#!/usr/bin/env python3
"""Exercise the real stdio server, including UTF-16 ranges and refusals."""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SERVER = Path(os.environ.get("LSP_BINARY", ROOT / "build/reports/lsp-refactor"))
messages = [{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}]
expected = {}
texts = {}
request_id = 2


def request(text, line, character, new_name="input", error=False, prepare=False):
    global request_id
    uri = f"file:///tmp/refactor-{request_id}.w"
    texts[uri] = text
    messages.append({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {
        "textDocument": {"uri": uri, "version": 7, "languageId": "tungsten", "text": text}}})
    params = {"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}
    if not prepare:
        params["newName"] = new_name
    messages.append({"jsonrpc": "2.0", "id": request_id,
                     "method": "textDocument/prepareRename" if prepare else "textDocument/rename", "params": params})
    expected[request_id] = {"error": error, "prepare": prepare, "uri": uri, "new_name": new_name}
    request_id += 1
    return request_id - 1


simple = "-> scale(value) (i64) i64\n  value * 2\n\n-> other(value)\n  value\n\n<< scale(21)\n"
simple_id = request(simple, 1, 3)
request(simple, 0, 10, prepare=True)
request(simple, 1, 3, "if", error=True)
request(simple, 1, 3, "newName", error=True)
request("-> scale(value, factor)\n  value + factor\n", 1, 3, "factor", error=True)
request("-> scale(value)\n  value + extra()\n", 1, 3, "extra", error=True)
request('-> label(value)\n  # value stays in the comment\n  "value"; value\n', 2, 12)
request('-> label(value)\n  "hello [value]"\n', 0, 10, error=True)
request("-> scale(value)\n  [1, 2].each -> (x)\n    value + x\n", 0, 10, error=True)
request("-> scale(value, obj)\n  obj.value + value\n", 1, 7, error=True)
request("-> scale(value:)\n  value\n", 1, 3, error=True)
request("## i64: value\n-> scale(value)\n  value + 1\n", 2, 3, error=True)
request("-> scale(value)\n  {value: value}\n", 0, 10, error=True)
unicode_text = '-> scale(value)\n  "😀"; value + 1\n'
unicode_col = len('  "😀"; '.encode("utf-16-le")) // 2
unicode_id = request(unicode_text, 1, unicode_col)

duplicate_uri = "file:///tmp/refactor-imports.w"
duplicate_text = "use core/math\nuse core/math\nuse core/math # preserve this comment\n<< 1\n"
messages.append({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {
    "textDocument": {"uri": duplicate_uri, "version": 3, "text": duplicate_text}}})
action_id = request_id
for only in (None, ["refactor"]):
    messages.append({"jsonrpc": "2.0", "id": request_id, "method": "textDocument/codeAction", "params": {
        "textDocument": {"uri": duplicate_uri}, "range": {"start": {"line": 0, "character": 0},
        "end": {"line": 3, "character": 0}}, "context": {"diagnostics": [], **({"only": only} if only else {})}}})
    request_id += 1
messages += [{"jsonrpc": "2.0", "id": request_id, "method": "shutdown", "params": {}},
             {"jsonrpc": "2.0", "method": "exit", "params": {}}]
payload = bytearray()
for message in messages:
    body = json.dumps(message, ensure_ascii=False).encode()
    payload.extend(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
result = subprocess.run([str(SERVER)], input=bytes(payload), stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, cwd=ROOT, timeout=40)
(ROOT / "build/reports/lsp-protocol.stdout").write_bytes(result.stdout)
(ROOT / "build/reports/lsp-protocol.stderr").write_bytes(result.stderr)
assert result.returncode == 0, result.stderr.decode(errors="replace")
data = result.stdout
responses = {}
while data:
    header, sep, rest = data.partition(b"\r\n\r\n")
    assert sep and header.startswith(b"Content-Length:"), data[:500]
    size = int(header.split(b":", 1)[1])
    message = json.loads(rest[:size])
    if "id" in message:
        responses[message["id"]] = message
    data = rest[size:]
assert responses[1]["result"]["capabilities"]["renameProvider"]["prepareProvider"]
assert responses[1]["result"]["capabilities"]["codeActionProvider"]["codeActionKinds"] == ["quickfix"]


def byte_offset(text, pos):
    lines = text.splitlines(keepends=True)
    preceding = "".join(lines[:pos["line"]])
    line = lines[pos["line"]]
    column = pos["character"]
    prefix = line.encode("utf-16-le")[:column * 2].decode("utf-16-le")
    return len((preceding + prefix).encode())


def apply_edits(text, edits):
    original = text.encode()
    spans = []
    for edit in edits:
        first = byte_offset(text, edit["range"]["start"])
        last = byte_offset(text, edit["range"]["end"])
        assert original[first:last] == b"value", (text, edit)
        spans.append((first, last, edit["newText"].encode()))
    for first, last, replacement in sorted(spans, reverse=True):
        original = original[:first] + replacement + original[last:]
    return original.decode()


changed = {}
for ident, check in expected.items():
    response = responses.get(ident)
    assert response is not None, (ident, result.stderr.decode())
    if check["error"]:
        assert "error" in response, (ident, response)
    elif check["prepare"]:
        assert response["result"]["placeholder"] == "value", response
    else:
        assert "result" in response, (ident, response)
        doc = response["result"]["documentChanges"][0]
        assert doc["textDocument"] == {"uri": check["uri"], "version": 7}
        assert len(doc["edits"]) == 2, doc
        changed[ident] = apply_edits(texts[check["uri"]], doc["edits"])
assert "-> other(value)\n  value" in changed[simple_id]
assert '"😀"; input + 1' in changed[unicode_id]
actions = responses[action_id]["result"]
assert len(actions) == 1, actions
action = actions[0]["edit"]["documentChanges"][0]
assert action["textDocument"]["version"] == 3
assert action["edits"][0]["range"] == {"start": {"line": 1, "character": 0}, "end": {"line": 2, "character": 0}}
assert responses[action_id + 1]["result"] == []

# Check the actual rewritten program, not only the shape of the edit response.
out = ROOT / "build/reports/lsp-refactor-check"
out.mkdir(exist_ok=True)
for label, text in (("before", simple), ("after", changed[simple_id])):
    src = out / (label + ".w")
    src.write_text(text)
    binary = out / label
    subprocess.run([str(ROOT / "bin/tungsten-compiler"), "compile", str(src), "--out", str(binary), "--no-lto"],
                   cwd=ROOT, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    assert subprocess.check_output([str(binary)], text=True).strip() == "42"
print(f"LSP refactoring: {len(expected)} rename/prepare cases, duplicate-import actions, and executable parity passed")
