# Forge Link specs — Web Linking header parsing and building (RFC 8288),
# plus the Request#links and Response#link / #links delegators. Before
# this the request/response surface could neither read a Link header
# (pagination, canonical, preload, API discovery) nor write one.
#
# Pure header logic: no sockets, no clock. Requests are built with
# Request.parse and responses with the Response writers, so every example
# runs under both the interpreter and compiled. Array results are checked
# by size + element, never by == (which is identity for compiled Arrays).
#
# NOTE: a literal "\[" / "\]" in a Tungsten string interpolates unless it
# is escaped — the IPv6-target example below escapes both.

use spec_helper

describe "Link.parse — shape" ->
  it "is empty for nil or blank input" ->
    expect(Link.parse(nil).empty?).to eq(true)
    expect(Link.parse("").empty?).to eq(true)
    expect(Link.parse("   ").empty?).to eq(true)
    expect(Link.parse(nil).size).to eq(0)

  it "parses a single entry" ->
    links = Link.parse("<https://api.example.com/items?page=2>; rel=\"next\"")
    expect(links.size).to eq(1)
    expect(links.empty?).to eq(false)
    expect(links[0].target).to eq("https://api.example.com/items?page=2")
    expect(links[0].rel).to eq("next")

  it "parses a bare target with no params" ->
    links = Link.parse("<https://example.com/doc>")
    expect(links.size).to eq(1)
    expect(links[0].target).to eq("https://example.com/doc")
    expect(links[0].rel).to be_nil

  it "keeps every entry, in header order" ->
    links = Link.parse("</p?page=1>; rel=\"first\", </p?page=3>; rel=\"next\", </p?page=9>; rel=\"last\"")
    expect(links.size).to eq(3)
    expect(links[0].target).to eq("/p?page=1")
    expect(links[1].target).to eq("/p?page=3")
    expect(links[2].target).to eq("/p?page=9")

  it "tolerates sloppy whitespace around commas and semicolons" ->
    links = Link.parse("  </a> ;  rel=\"next\"  ,   </b>;rel=\"prev\"  ")
    expect(links.size).to eq(2)
    expect(links[0].target).to eq("/a")
    expect(links[0].rel).to eq("next")
    expect(links[1].rel).to eq("prev")

  it "ignores a trailing or doubled comma" ->
    links = Link.parse("</a>; rel=\"next\",, </b>; rel=\"prev\",")
    expect(links.size).to eq(2)

  it "accepts an empty target (a same-document reference)" ->
    links = Link.parse("<>; rel=\"canonical\"")
    expect(links.size).to eq(1)
    expect(links[0].target).to eq("")
    expect(links[0].rel).to eq("canonical")

  it "accepts a bracketed IPv6 authority in the target" ->
    links = Link.parse("<http://\[2001:db8::1\]:8080/p>; rel=\"next\"")
    expect(links.size).to eq(1)
    expect(links[0].target).to eq("http://\[2001:db8::1\]:8080/p")

describe "Link.parse — params" ->
  it "reads a quoted param value" ->
    v = Link.parse("</a>; rel=\"next\"; title=\"Page two\"")[0]
    expect(v.rel).to eq("next")
    expect(v.title).to eq("Page two")

  it "reads an unquoted token param value" ->
    v = Link.parse("</a>; rel=next; hreflang=en")[0]
    expect(v.rel).to eq("next")
    expect(v.hreflang).to eq("en")

  it "downcases param names (case-insensitive)" ->
    v = Link.parse("</a>; REL=\"next\"; Title=\"T\"; TYPE=\"text/html\"")[0]
    expect(v.rel).to eq("next")
    expect(v.title).to eq("T")
    expect(v.type).to eq("text/html")

  it "looks params up case-insensitively" ->
    v = Link.parse("</a>; rel=\"next\"")[0]
    expect(v.param("REL")).to eq("next")
    expect(v.has?("Rel")).to eq(true)
    expect(v.has?("title")).to eq(false)

  it "stores a valueless param as true" ->
    v = Link.parse("</a>; rel=\"preload\"; nopush")[0]
    expect(v.param("nopush")).to eq(true)
    expect(v.has?("nopush")).to eq(true)

  it "keeps the FIRST occurrence of a duplicate param (RFC 8288)" ->
    v = Link.parse("</a>; rel=\"next\"; rel=\"prev\"; title=\"one\"; title=\"two\"")[0]
    expect(v.rel).to eq("next")
    expect(v.title).to eq("one")

  it "unescapes a backslash escape inside a quoted value" ->
    v = Link.parse("</a>; title=\"a \\\"quoted\\\" word\"")[0]
    expect(v.title).to eq("a \"quoted\" word")

  it "is nil for an absent param and for a valueless well-known param" ->
    v = Link.parse("</a>; rel=\"next\"; title")[0]
    expect(v.title).to be_nil
    expect(v.type).to be_nil
    expect(v.media).to be_nil
    expect(v.anchor).to be_nil

  it "reads every well-known param" ->
    header = "</fr>; rel=\"alternate\"; hreflang=\"fr\"; media=\"screen\"; type=\"text/html\"; anchor=\"#c\"; title=\"FR\""
    v = Link.parse(header)[0]
    expect(v.rel).to eq("alternate")
    expect(v.hreflang).to eq("fr")
    expect(v.media).to eq("screen")
    expect(v.type).to eq("text/html")
    expect(v.anchor).to eq("#c")
    expect(v.title).to eq("FR")

  it "exposes an RFC 8187 ext-value param raw" ->
    v = Link.parse("</a>; rel=\"next\"; title*=UTF-8''%e2%82%ac")[0]
    expect(v.param("title*")).to eq("UTF-8''%e2%82%ac")

describe "Link.parse — quote- and angle-aware splitting" ->
  it "does not split on a comma inside the target URI" ->
    links = Link.parse("</p?ids=1,2,3>; rel=\"next\"")
    expect(links.size).to eq(1)
    expect(links[0].target).to eq("/p?ids=1,2,3")

  it "does not split on a semicolon inside the target URI" ->
    v = Link.parse("</p;v=1;w=2>; rel=\"next\"")[0]
    expect(v.target).to eq("/p;v=1;w=2")
    expect(v.rel).to eq("next")

  it "does not split on a comma inside a quoted param value" ->
    links = Link.parse("</a>; rel=\"next\"; title=\"One, Two\", </b>; rel=\"prev\"")
    expect(links.size).to eq(2)
    expect(links[0].title).to eq("One, Two")
    expect(links[1].rel).to eq("prev")

  it "does not split on a semicolon inside a quoted param value" ->
    v = Link.parse("</a>; rel=\"next\"; title=\"a;b\"")[0]
    expect(v.title).to eq("a;b")
    expect(v.rel).to eq("next")

  it "treats an angle bracket inside a quoted value as literal text" ->
    v = Link.parse("</a>; rel=\"next\"; title=\"1 < 2\"")[0]
    expect(v.title).to eq("1 < 2")
    expect(v.target).to eq("/a")

describe "Link.parse — malformed entries are skipped, never raised" ->
  it "skips an entry with no angle-bracketed target" ->
    links = Link.parse("rel=\"next\"")
    expect(links.empty?).to eq(true)

  it "skips an entry whose target is never closed" ->
    links = Link.parse("<https://example.com/p; rel=\"next\"")
    expect(links.empty?).to eq(true)

  it "keeps the good entries around a bad one" ->
    links = Link.parse("</a>; rel=\"first\", garbage, </b>; rel=\"next\"")
    expect(links.size).to eq(2)
    expect(links[0].rel).to eq("first")
    expect(links[1].rel).to eq("next")

  it "drops a param with an empty name" ->
    v = Link.parse("</a>; =oops; rel=\"next\"")[0]
    expect(v.rel).to eq("next")
    expect(v.params.size).to eq(1)

describe "LinkValue — relation types" ->
  it "splits a multi-valued rel" ->
    rels = Link.parse("</a>; rel=\"prev index\"")[0].rels
    expect(rels.size).to eq(2)
    expect(rels[0]).to eq("prev")
    expect(rels[1]).to eq("index")

  it "matches any of a multi-valued rel" ->
    v = Link.parse("</a>; rel=\"prev index\"")[0]
    expect(v.rel?("prev")).to eq(true)
    expect(v.rel?("index")).to eq(true)
    expect(v.rel?("next")).to eq(false)

  it "matches a relation type case-insensitively" ->
    v = Link.parse("</a>; rel=\"NEXT\"")[0]
    expect(v.rel?("next")).to eq(true)
    expect(v.rel?("Next")).to eq(true)
    expect(v.rels[0]).to eq("next")

  it "keeps the rel value verbatim while rels downcases" ->
    v = Link.parse("</a>; rel=\"NEXT\"")[0]
    expect(v.rel).to eq("NEXT")

  it "has no relation types when rel is absent" ->
    v = Link.parse("</a>; title=\"x\"")[0]
    expect(v.rels.size).to eq(0)
    expect(v.rel?("next")).to eq(false)

  it "collapses whitespace runs between relation types" ->
    rels = Link.parse("</a>; rel=\"  prev   next \"")[0].rels
    expect(rels.size).to eq(2)
    expect(rels[0]).to eq("prev")
    expect(rels[1]).to eq("next")

describe "Link — lookup by relation type" ->
  it "finds the entry for a rel and its href" ->
    links = Link.parse("</p?page=1>; rel=\"prev\", </p?page=3>; rel=\"next\"")
    expect(links.href("next")).to eq("/p?page=3")
    expect(links.href("prev")).to eq("/p?page=1")
    expect(links.find("next").rel).to eq("next")

  it "is nil for a rel no entry declares" ->
    links = Link.parse("</p?page=3>; rel=\"next\"")
    expect(links.href("last")).to be_nil
    expect(links.find("last")).to be_nil
    expect(links.has?("last")).to eq(false)
    expect(links.has?("next")).to eq(true)

  it "finds the FIRST entry when several share a rel" ->
    links = Link.parse("</a>; rel=\"alternate\", </b>; rel=\"alternate\"")
    expect(links.href("alternate")).to eq("/a")

  it "returns every entry with a rel via all" ->
    links = Link.parse("</a>; rel=\"alternate\"; hreflang=\"en\", </b>; rel=\"alternate\"; hreflang=\"fr\", </c>; rel=\"next\"")
    matches = links.all("alternate")
    expect(matches.size).to eq(2)
    expect(matches[0].hreflang).to eq("en")
    expect(matches[1].hreflang).to eq("fr")
    expect(links.all("nope").size).to eq(0)

  it "matches a lookup against a multi-valued rel" ->
    links = Link.parse("</a>; rel=\"prev index\"")
    expect(links.href("index")).to eq("/a")

  it "lists every distinct relation type in first-seen order" ->
    rels = Link.parse("</a>; rel=\"first prev\", </b>; rel=\"next\", </c>; rel=\"prev\"").rels
    expect(rels.size).to eq(3)
    expect(rels[0]).to eq("first")
    expect(rels[1]).to eq("prev")
    expect(rels[2]).to eq("next")

  it "walks the entries in order with each" ->
    seen = ""
    Link.parse("</a>; rel=\"first\", </b>; rel=\"next\"").each -> (v)
      seen = seen + v.target
    expect(seen).to eq("/a/b")

  it "exposes the entries as an Array" ->
    entries = Link.parse("</a>; rel=\"next\"").to_a
    expect(entries.size).to eq(1)
    expect(entries[0].target).to eq("/a")

describe "Link — building" ->
  it "builds a link-value from a target and Symbol-keyed params" ->
    v = LinkValue.new("/p?page=2", {rel: "next"})
    expect(v.to_s).to eq("</p?page=2>; rel=\"next\"")

  it "accepts String-keyed and mixed-case params when building" ->
    v = LinkValue.new("/a", {"REL" => "next"})
    expect(v.rel).to eq("next")
    expect(v.to_s).to eq("</a>; rel=\"next\"")

  it "drops a nil param value when building" ->
    v = LinkValue.new("/a", {rel: "next", title: nil})
    expect(v.params.size).to eq(1)
    expect(v.title).to be_nil

  it "emits a valueless param bare" ->
    v = LinkValue.new("/a", {rel: "preload", nopush: true})
    expect(v.to_s).to eq("</a>; rel=\"preload\"; nopush")

  it "escapes a quote inside an emitted value" ->
    v = LinkValue.new("/a", {title: "say \"hi\""})
    expect(v.to_s).to eq("</a>; title=\"say \\\"hi\\\"\"")

  it "joins several entries with a comma" ->
    header = Link.new.add("/p?page=1", {rel: "first"}).add("/p?page=3", {rel: "next"}).to_s
    expect(header).to eq("</p?page=1>; rel=\"first\", </p?page=3>; rel=\"next\"")

  it "is an empty string for an empty Link" ->
    expect(Link.new.to_s).to eq("")

  it "starts each new Link with its own entries" ->
    a = Link.new.add("/a", {rel: "next"})
    b = Link.new
    expect(a.size).to eq(1)
    expect(b.size).to eq(0)

  it "round-trips build -> parse -> build" ->
    built = Link.new.add("/p?ids=1,2", {rel: "next", title: "A, B"}).to_s
    back = Link.parse(built)
    expect(back.size).to eq(1)
    expect(back.href("next")).to eq("/p?ids=1,2")
    expect(back[0].title).to eq("A, B")
    expect(back.to_s).to eq(built)

describe "Request#links" ->
  it "parses the request Link header" ->
    req = Request.parse("GET /p HTTP/1.1\r\nLink: </schema>; rel=\"describedby\"\r\n\r\n")
    expect(req.links.size).to eq(1)
    expect(req.links.href("describedby")).to eq("/schema")

  it "is an empty Link when the header is absent" ->
    req = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.links.empty?).to eq(true)

  it "finds the header case-insensitively" ->
    req = Request.parse("GET / HTTP/1.1\r\nlink: </a>; rel=\"next\"\r\n\r\n")
    expect(req.links.href("next")).to eq("/a")

  it "reads a real paginated API header" ->
    header = "<https://api.example.com/items?page=3>; rel=\"next\", <https://api.example.com/items?page=9>; rel=\"last\", <https://api.example.com/items?page=1>; rel=\"first\", <https://api.example.com/items?page=1>; rel=\"prev\""
    req = Request.parse("GET /items?page=2 HTTP/1.1\r\nLink: " + header + "\r\n\r\n")
    links = req.links
    expect(links.size).to eq(4)
    expect(links.href("next")).to eq("https://api.example.com/items?page=3")
    expect(links.href("last")).to eq("https://api.example.com/items?page=9")

describe "Response#link and #links" ->
  it "writes a Link header a client can parse back" ->
    resp = Response.text("page 2").link("/p?page=3", {rel: "next"})
    expect(resp.headers["Link"]).to eq("</p?page=3>; rel=\"next\"")
    expect(resp.links.href("next")).to eq("/p?page=3")

  it "appends further entries and chains" ->
    resp = Response.ok("x").link("/p?page=1", {rel: "first"}).link("/p?page=3", {rel: "next"})
    expect(resp.headers["Link"]).to eq("</p?page=1>; rel=\"first\", </p?page=3>; rel=\"next\"")
    expect(resp.links.size).to eq(2)

  it "carries extra params through" ->
    resp = Response.ok("x").link("/style.css", {rel: "preload", type: "text/css"})
    v = resp.links[0]
    expect(v.rel).to eq("preload")
    expect(v.type).to eq("text/css")

  it "appends to a Link header set by hand, keeping its casing" ->
    resp = Response.ok("x").header("link", "</a>; rel=\"first\"")
    resp.link("/b", {rel: "next"})
    expect(resp.headers["link"]).to eq("</a>; rel=\"first\", </b>; rel=\"next\"")
    expect(resp.links.size).to eq(2)

  it "is an empty Link when no Link header is set" ->
    expect(Response.ok("x").links.empty?).to eq(true)

  it "survives the response serialization round trip" ->
    http = Response.ok("body").link("/p?page=2", {rel: "next"}).to_http
    expect(http.include?("Link: </p?page=2>; rel=\"next\"")).to eq(true)

spec_summary
