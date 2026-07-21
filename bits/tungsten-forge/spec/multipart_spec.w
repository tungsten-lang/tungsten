# Forge multipart specs — Multipart (multipart/form-data body parsing) and
# the Request methods that delegate to it (Request#multipart?, and
# Request#multipart_body over a parsed request). Before lib/multipart.w a
# file upload / mixed file+field form (`enctype="multipart/form-data"`) had
# no request-surface support at all; these lock in the behaviour.
#
# No sockets: bodies are built as plain strings and parsed directly, so
# everything here runs under both engines (interpreted and compiled).
#
# Style note: never chain a call off a `?` method (`file?.to_s` lexes as
# safe navigation, which the interpreter does not implement), so predicate
# results are bound to a local before being asserted.

use spec_helper

# Build a multipart body from an array of already-formatted part blocks,
# joined by the boundary delimiter and closed with the final "--boundary--".
-> mp_body(boundary, blocks)
  out = ""
  blocks.each -> (block)
    out = out + "--" + boundary + "\r\n" + block + "\r\n"
  out + "--" + boundary + "--\r\n"

describe "Multipart.boundary" ->
  it "reads a bare boundary parameter" ->
    b = Multipart.boundary("multipart/form-data; boundary=----FormBoundary123")
    expect(b).to eq("----FormBoundary123")

  it "unwraps a quoted boundary parameter" ->
    b = Multipart.boundary("multipart/form-data; boundary=\"abc def\"")
    expect(b).to eq("abc def")

  it "matches the parameter name case-insensitively and preserves value case" ->
    b = Multipart.boundary("multipart/form-data; BOUNDARY=WebKitABC")
    expect(b).to eq("WebKitABC")

  it "is nil when there is no boundary parameter" ->
    expect(Multipart.boundary("text/plain")).to be_nil

  it "is nil for a nil content type" ->
    expect(Multipart.boundary(nil)).to be_nil

describe "Multipart.parse" ->
  it "parses a single form field" ->
    body = mp_body("B", ["Content-Disposition: form-data; name=\"title\"\r\n\r\nHello World"])
    form = Multipart.parse(body, "multipart/form-data; boundary=B")
    expect(form.size).to eq(1)
    expect(form.field("title")).to eq("Hello World")

  it "parses multiple fields in wire order" ->
    body = mp_body("B", [
      "Content-Disposition: form-data; name=\"a\"\r\n\r\n1",
      "Content-Disposition: form-data; name=\"b\"\r\n\r\n2"
    ])
    form = Multipart.parse(body, "multipart/form-data; boundary=B")
    expect(form.size).to eq(2)
    expect(form.field("a")).to eq("1")
    expect(form.field("b")).to eq("2")

  it "parses a file part with filename and content type" ->
    body = mp_body("B", [
      "Content-Disposition: form-data; name=\"avatar\"; filename=\"pic.png\"\r\nContent-Type: image/png\r\n\r\nRAWBYTES"
    ])
    form = Multipart.parse(body, "multipart/form-data; boundary=B")
    f = form.file("avatar")
    expect(f.name).to eq("avatar")
    expect(f.filename).to eq("pic.png")
    expect(f.content_type).to eq("image/png")
    expect(f.body).to eq("RAWBYTES")
    is_file = f.file?
    expect(is_file).to eq(true)

  it "reads name correctly even though filename= contains the bytes name=" ->
    body = mp_body("B", [
      "Content-Disposition: form-data; name=\"doc\"; filename=\"report.pdf\"\r\n\r\nPDF"
    ])
    form = Multipart.parse(body, "multipart/form-data; boundary=B")
    p = form.part("doc")
    expect(p.name).to eq("doc")
    expect(p.filename).to eq("report.pdf")

  it "leaves a plain field's filename nil and file? false" ->
    body = mp_body("B", ["Content-Disposition: form-data; name=\"note\"\r\n\r\nhi"])
    form = Multipart.parse(body, "multipart/form-data; boundary=B")
    p = form.part("note")
    expect(p.filename).to be_nil
    not_file = p.file?
    expect(not_file).to eq(false)

  it "leaves a part without an explicit Content-Type nil" ->
    body = mp_body("B", ["Content-Disposition: form-data; name=\"x\"\r\n\r\nv"])
    form = Multipart.parse(body, "multipart/form-data; boundary=B")
    expect(form.part("x").content_type).to be_nil

  it "preserves CRLFs inside a value and strips the trailing delimiter CRLF" ->
    body = mp_body("B", ["Content-Disposition: form-data; name=\"m\"\r\n\r\nline1\r\nline2"])
    form = Multipart.parse(body, "multipart/form-data; boundary=B")
    expect(form.field("m")).to eq("line1\r\nline2")

  it "does not false-split on a --boundary that lacks a leading CRLF inside a value" ->
    body = mp_body("Bnd", ["Content-Disposition: form-data; name=\"x\"\r\n\r\nkeep--Bnd-inside"])
    form = Multipart.parse(body, "multipart/form-data; boundary=Bnd")
    expect(form.size).to eq(1)
    expect(form.field("x")).to eq("keep--Bnd-inside")

  it "keeps all parts for a duplicated name, first wins on lookup" ->
    body = mp_body("B", [
      "Content-Disposition: form-data; name=\"x\"\r\n\r\n1",
      "Content-Disposition: form-data; name=\"x\"\r\n\r\n2"
    ])
    form = Multipart.parse(body, "multipart/form-data; boundary=B")
    expect(form.size).to eq(2)
    expect(form.field("x")).to eq("1")

  it "ignores a preamble and epilogue around the parts" ->
    core = mp_body("B", ["Content-Disposition: form-data; name=\"x\"\r\n\r\nv"])
    body = "preamble noise\r\n" + core + "trailing epilogue"
    form = Multipart.parse(body, "multipart/form-data; boundary=B")
    expect(form.size).to eq(1)
    expect(form.field("x")).to eq("v")

  it "yields an empty form when the content type has no boundary" ->
    body = mp_body("B", ["Content-Disposition: form-data; name=\"x\"\r\n\r\nv"])
    form = Multipart.parse(body, "text/plain")
    expect(form.size).to eq(0)
    empty = form.empty?
    expect(empty).to eq(true)

  it "yields an empty form for a nil or empty body" ->
    expect(Multipart.parse(nil, "multipart/form-data; boundary=B").size).to eq(0)
    expect(Multipart.parse("", "multipart/form-data; boundary=B").size).to eq(0)

describe "MultipartForm accessors" ->
  it "returns nil from field and file for an absent name" ->
    body = mp_body("B", ["Content-Disposition: form-data; name=\"x\"\r\n\r\nv"])
    form = Multipart.parse(body, "multipart/form-data; boundary=B")
    expect(form.field("missing")).to be_nil
    expect(form.file("missing")).to be_nil

  it "file returns nil when the named part is a plain field, not a file" ->
    body = mp_body("B", ["Content-Disposition: form-data; name=\"x\"\r\n\r\nv"])
    form = Multipart.parse(body, "multipart/form-data; boundary=B")
    expect(form.file("x")).to be_nil

  it "files returns only the file parts" ->
    body = mp_body("B", [
      "Content-Disposition: form-data; name=\"field\"\r\n\r\nplain",
      "Content-Disposition: form-data; name=\"up\"; filename=\"a.txt\"\r\n\r\nFILE"
    ])
    form = Multipart.parse(body, "multipart/form-data; boundary=B")
    expect(form.files.size).to eq(1)
    expect(form.files[0].filename).to eq("a.txt")

describe "Request#multipart?" ->
  it "is true for a multipart/form-data content type" ->
    req = Request.parse("POST /u HTTP/1.1\r\nContent-Type: multipart/form-data; boundary=B\r\n\r\n")
    mp = req.multipart?
    expect(mp).to eq(true)

  it "is false for an urlencoded form" ->
    req = Request.parse("POST /u HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r\n\r\na=1")
    mp = req.multipart?
    expect(mp).to eq(false)

describe "Request#multipart_body" ->
  it "parses fields and files from a parsed request" ->
    body = mp_body("B", [
      "Content-Disposition: form-data; name=\"title\"\r\n\r\nGreetings",
      "Content-Disposition: form-data; name=\"file\"; filename=\"hi.txt\"\r\nContent-Type: text/plain\r\n\r\nDATA"
    ])
    raw = "POST /u HTTP/1.1\r\nContent-Type: multipart/form-data; boundary=B\r\nContent-Length: [body.size]\r\n\r\n[body]"
    req = Request.parse(raw)
    form = req.multipart_body
    expect(form.field("title")).to eq("Greetings")
    up = form.file("file")
    expect(up.filename).to eq("hi.txt")
    expect(up.body).to eq("DATA")

  it "is nil when the request is not multipart" ->
    req = Request.parse("POST /u HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}")
    expect(req.multipart_body).to be_nil

spec_summary
