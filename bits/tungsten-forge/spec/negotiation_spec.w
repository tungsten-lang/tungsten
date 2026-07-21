# Forge content-negotiation specs — Negotiation (Accept-family header
# parsing with q-values and server-offer selection) and the Request
# methods that delegate to it (#accepts?, #preferred_type,
# #preferred_language, #preferred_encoding, #accepted_media_types).
#
# No sockets: requests are built with Request.parse, so everything here
# runs under both engines. Arrays are asserted by size/index rather than
# `==` (compiled Array equality is identity).
#
# Style note: never chain a call off a `?` method (`accepts?.to_s` lexes
# as safe navigation, which the interpreter does not implement).

use spec_helper

describe "Negotiation.parse" ->
  it "returns one entry per comma-separated range, lowercased" ->
    entries = Negotiation.parse("Text/HTML, application/json")
    expect(entries.size).to eq(2)
    expect(entries[0][:value]).to eq("text/html")
    expect(entries[1][:value]).to eq("application/json")

  it "defaults an absent q to 1.0" ->
    entries = Negotiation.parse("text/html")
    expect(entries[0][:q]).to eq(1.0)

  it "reads a q parameter and ignores other parameters" ->
    entries = Negotiation.parse("text/html;level=1;q=0.5")
    expect(entries[0][:value]).to eq("text/html")
    expect(entries[0][:q]).to eq(0.5)

  it "clamps an out-of-range q into 0.0..1.0" ->
    entries = Negotiation.parse("a/b;q=9, c/d;q=-2")
    expect(entries[0][:q]).to eq(1.0)
    expect(entries[1][:q]).to eq(0.0)

  it "returns an empty array for nil or empty input" ->
    expect(Negotiation.parse(nil).size).to eq(0)
    expect(Negotiation.parse("").size).to eq(0)

describe "Negotiation.accepts? (media)" ->
  it "matches an exact media type" ->
    expect(Negotiation.accepts?("text/html", "text/html", :media)).to eq(true)

  it "matches a type/* subtype wildcard" ->
    expect(Negotiation.accepts?("text/*", "text/html", :media)).to eq(true)

  it "matches the */* wildcard" ->
    expect(Negotiation.accepts?("*/*", "image/png", :media)).to eq(true)

  it "rejects a type the header does not list" ->
    expect(Negotiation.accepts?("text/html", "application/json", :media)).to eq(false)

  it "treats a nil or empty header as accept-anything" ->
    expect(Negotiation.accepts?(nil, "anything/here", :media)).to eq(true)
    expect(Negotiation.accepts?("", "anything/here", :media)).to eq(true)

  it "honours an explicit q=0 rejection" ->
    expect(Negotiation.accepts?("text/html;q=0", "text/html", :media)).to eq(false)

  it "lets a specific q=0 override a broader wildcard" ->
    expect(Negotiation.accepts?("application/json;q=0, */*", "application/json", :media)).to eq(false)
    expect(Negotiation.accepts?("application/json;q=0, */*", "text/html", :media)).to eq(true)

describe "Negotiation.best (media)" ->
  it "picks the offer with the highest quality" ->
    best = Negotiation.best("text/html,application/json;q=0.9", ["application/json", "text/html"], :media)
    expect(best).to eq("text/html")

  it "picks a lower-listed offer when its quality is higher" ->
    best = Negotiation.best("application/json;q=0.9,text/html;q=0.8", ["text/html", "application/json"], :media)
    expect(best).to eq("application/json")

  it "returns the server's first offer when the client has no preference" ->
    expect(Negotiation.best("*/*", ["application/json", "text/html"], :media)).to eq("application/json")
    expect(Negotiation.best("", ["a/b", "c/d"], :media)).to eq("a/b")

  it "returns nil when the client accepts none of the offers" ->
    expect(Negotiation.best("text/plain", ["application/json"], :media)).to be_nil

  it "handles a real browser Accept header" ->
    header = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    expect(Negotiation.best(header, ["application/json", "text/html"], :media)).to eq("text/html")

  it "resolves each offer against its most specific matching range" ->
    # text/html matches text/* (q=1); text/plain matches its exact q=0.1.
    best = Negotiation.best("text/*;q=1, text/plain;q=0.1", ["text/plain", "text/html"], :media)
    expect(best).to eq("text/html")

  it "returns nil for an empty offer list" ->
    expect(Negotiation.best("*/*", [], :media)).to be_nil

describe "Negotiation.best (lang)" ->
  it "prefers the exact tag over a prefix match" ->
    best = Negotiation.best("en-US,en;q=0.9,fr;q=0.5", ["fr", "en"], :lang)
    expect(best).to eq("en")

  it "matches a base range against a regional offer (en -> en-US)" ->
    expect(Negotiation.best("en", ["en-US"], :lang)).to eq("en-US")

  it "returns the first offer for the * wildcard" ->
    expect(Negotiation.best("*", ["de", "fr"], :lang)).to eq("de")

  it "returns nil when no offered language matches" ->
    expect(Negotiation.best("es", ["en", "fr"], :lang)).to be_nil

describe "Negotiation.best (token / encoding)" ->
  it "picks the highest-quality coding" ->
    expect(Negotiation.best("gzip, br;q=0.9", ["br", "gzip"], :token)).to eq("gzip")

  it "rejects a coding refused with q=0 even under a wildcard" ->
    expect(Negotiation.best("gzip;q=0, *", ["gzip"], :token)).to be_nil

  it "returns the first offer for the * wildcard" ->
    expect(Negotiation.best("*", ["gzip", "br"], :token)).to eq("gzip")

describe "Negotiation.ranked" ->
  it "orders ranges by descending quality" ->
    ranked = Negotiation.ranked("text/html;q=0.8,application/json;q=0.9")
    expect(ranked.size).to eq(2)
    expect(ranked[0]).to eq("application/json")
    expect(ranked[1]).to eq("text/html")

  it "keeps original order for equal quality (stable)" ->
    ranked = Negotiation.ranked("text/html,application/json")
    expect(ranked[0]).to eq("text/html")
    expect(ranked[1]).to eq("application/json")

  it "drops q=0 rejections" ->
    ranked = Negotiation.ranked("text/html,application/json;q=0")
    expect(ranked.size).to eq(1)
    expect(ranked[0]).to eq("text/html")

  it "is empty for a nil or empty header" ->
    expect(Negotiation.ranked(nil).size).to eq(0)
    expect(Negotiation.ranked("").size).to eq(0)

describe "Request content negotiation" ->
  it "#accepts? reads the Accept header" ->
    req = Request.parse("GET /x HTTP/1.1\r\nAccept: text/html,application/json;q=0.9\r\n\r\n")
    expect(req.accepts?("application/json")).to eq(true)
    expect(req.accepts?("text/plain")).to eq(false)

  it "#accepts? accepts anything when the Accept header is absent" ->
    req = Request.parse("GET /x HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.accepts?("application/json")).to eq(true)

  it "#preferred_type chooses among server offers" ->
    req = Request.parse("GET /x HTTP/1.1\r\nAccept: application/json;q=0.9,text/html\r\n\r\n")
    expect(req.preferred_type(["application/json", "text/html"])).to eq("text/html")

  it "#preferred_language reads Accept-Language" ->
    req = Request.parse("GET /x HTTP/1.1\r\nAccept-Language: fr-CH, fr;q=0.9, en;q=0.8\r\n\r\n")
    expect(req.preferred_language(["en", "fr"])).to eq("fr")

  it "#preferred_encoding reads Accept-Encoding and honours q=0" ->
    req = Request.parse("GET /x HTTP/1.1\r\nAccept-Encoding: br, gzip;q=0\r\n\r\n")
    expect(req.preferred_encoding(["gzip", "br"])).to eq("br")

  it "#accepted_media_types lists ranges best-first" ->
    req = Request.parse("GET /x HTTP/1.1\r\nAccept: text/plain;q=0.5,text/html\r\n\r\n")
    ranked = req.accepted_media_types
    expect(ranked.size).to eq(2)
    expect(ranked[0]).to eq("text/html")
    expect(ranked[1]).to eq("text/plain")

spec_summary
