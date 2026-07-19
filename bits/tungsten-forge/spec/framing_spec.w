# Forge request-framing / keep-alive specs — the pure string halves of the
# server's connection read-loop (Server.request_length / content_length_in)
# and Request#keep_alive?. No sockets: everything here runs under both
# engines (interpreted and compiled).
#
# Style notes: never chain a call off a `?` method (`keep_alive?.to_s`
# lexes as safe navigation, which the interpreter does not implement) —
# bind to a local first.

use spec_helper

describe "Server.request_length" ->
  it "returns 0 while the header block is incomplete" ->
    expect(Server.request_length("")).to eq(0)
    expect(Server.request_length("GET / HTTP/1.1\r\nHost: x\r\n")).to eq(0)

  it "frames a bare GET at the header terminator" ->
    raw = "GET /a HTTP/1.1\r\nHost: x\r\n\r\n"
    expect(Server.request_length(raw)).to eq(raw.size)

  it "includes Content-Length bytes of body" ->
    raw = "POST /e HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"
    expect(Server.request_length(raw)).to eq(raw.size)

  it "returns 0 until the full body has arrived" ->
    expect(Server.request_length("POST /e HTTP/1.1\r\nContent-Length: 5\r\n\r\nhel")).to eq(0)

  it "frames only the first of two pipelined requests" ->
    first = "GET /a HTTP/1.1\r\nHost: x\r\n\r\n"
    second = "POST /e HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"
    expect(Server.request_length(first + second)).to eq(first.size)

  it "reads Content-Length case-insensitively" ->
    raw = "POST /e HTTP/1.1\r\ncontent-length: 2\r\n\r\nok"
    expect(Server.request_length(raw)).to eq(raw.size)

describe "Server.content_length_in" ->
  it "defaults to 0 without a Content-Length header" ->
    expect(Server.content_length_in("GET / HTTP/1.1\r\nHost: x")).to eq(0)

  it "parses the declared length" ->
    expect(Server.content_length_in("POST /e HTTP/1.1\r\nContent-Length: 128")).to eq(128)

describe "Request#keep_alive?" ->
  it "defaults to keep-alive for HTTP/1.1" ->
    req = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    keep = req.keep_alive?
    expect(keep).to eq(true)

  it "honors Connection: close on HTTP/1.1 (case-insensitive)" ->
    req = Request.parse("GET / HTTP/1.1\r\nConnection: Close\r\n\r\n")
    keep = req.keep_alive?
    expect(keep).to eq(false)

  it "defaults to close for HTTP/1.0" ->
    req = Request.parse("GET / HTTP/1.0\r\nHost: x\r\n\r\n")
    keep = req.keep_alive?
    expect(keep).to eq(false)

  it "honors Connection: keep-alive opt-in on HTTP/1.0" ->
    req = Request.parse("GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n")
    keep = req.keep_alive?
    expect(keep).to eq(true)

spec_summary
