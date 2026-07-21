# Forge byte-range specs — ByteRange (RFC 7233 Range-header parsing and
# resolution) and the Request methods that delegate to it (#range_header,
# #ranges). Before ByteRange the request surface could not read a Range
# header, so partial-content (HTTP 206) serving was impossible without an
# app re-deriving the satisfiability and clamping rules by hand.
#
# No sockets: requests are built with Request.parse, so everything here
# runs under both engines (interpreted and compiled). Resolved ranges are
# asserted by .start/.finish/.length rather than by Array `==` (compiled
# Array equality is identity).

use spec_helper

describe "ByteRange.parse (syntax)" ->
  it "returns nil for an absent or empty header" ->
    expect(ByteRange.parse(nil)).to be_nil
    expect(ByteRange.parse("")).to be_nil

  it "returns nil for a range unit other than bytes" ->
    expect(ByteRange.parse("items=0-1")).to be_nil

  it "returns nil for a valueless range unit" ->
    expect(ByteRange.parse("bytes=")).to be_nil

  it "parses a single closed range" ->
    specs = ByteRange.parse("bytes=0-499")
    expect(specs.size).to eq(1)
    expect(specs[0][:first]).to eq(0)
    expect(specs[0][:last]).to eq(499)
    expect(specs[0][:suffix]).to be_nil

  it "parses an open-ended range" ->
    specs = ByteRange.parse("bytes=500-")
    expect(specs.size).to eq(1)
    expect(specs[0][:first]).to eq(500)
    expect(specs[0][:last]).to be_nil

  it "parses a suffix range" ->
    specs = ByteRange.parse("bytes=-500")
    expect(specs.size).to eq(1)
    expect(specs[0][:suffix]).to eq(500)
    expect(specs[0][:first]).to be_nil

  it "parses a multi-range set in order" ->
    specs = ByteRange.parse("bytes=0-0,500-999,-100")
    expect(specs.size).to eq(3)
    expect(specs[0][:last]).to eq(0)
    expect(specs[1][:first]).to eq(500)
    expect(specs[2][:suffix]).to eq(100)

  it "trims optional whitespace around commas" ->
    specs = ByteRange.parse("bytes=0-99 ,  200-299")
    expect(specs.size).to eq(2)
    expect(specs[1][:first]).to eq(200)

  it "tolerates a leading, doubled, or trailing comma" ->
    specs = ByteRange.parse("bytes=,0-0,,-1,")
    expect(specs.size).to eq(2)

  it "tolerates whitespace around the unit and equals sign" ->
    specs = ByteRange.parse("bytes = 0-9")
    expect(specs.size).to eq(1)
    expect(specs[0][:last]).to eq(9)

  it "returns nil for a non-numeric bound" ->
    expect(ByteRange.parse("bytes=abc")).to be_nil
    expect(ByteRange.parse("bytes=x-5")).to be_nil
    expect(ByteRange.parse("bytes=0-y")).to be_nil

  it "returns nil when first-byte-pos exceeds last-byte-pos" ->
    expect(ByteRange.parse("bytes=10-5")).to be_nil

  it "returns nil for a spec with more than one dash" ->
    expect(ByteRange.parse("bytes=1-2-3")).to be_nil

  it "returns nil for a bare dash or empty suffix" ->
    expect(ByteRange.parse("bytes=-")).to be_nil

  it "invalidates the whole set when any spec is malformed" ->
    expect(ByteRange.parse("bytes=0-9,bad")).to be_nil

describe "ByteRange.resolve" ->
  it "returns nil when there is no usable Range header" ->
    expect(ByteRange.resolve(nil, 1000)).to be_nil
    expect(ByteRange.resolve("items=0-1", 1000)).to be_nil

  it "resolves a closed range within bounds" ->
    ranges = ByteRange.resolve("bytes=0-499", 1000)
    expect(ranges.size).to eq(1)
    expect(ranges[0].start).to eq(0)
    expect(ranges[0].finish).to eq(499)
    expect(ranges[0].length).to eq(500)
    expect(ranges[0].total).to eq(1000)

  it "clamps a last-byte-pos at or past the end to total-1" ->
    ranges = ByteRange.resolve("bytes=0-999", 500)
    expect(ranges[0].finish).to eq(499)
    expect(ranges[0].length).to eq(500)

  it "resolves an open-ended range to the end of the resource" ->
    ranges = ByteRange.resolve("bytes=500-", 1000)
    expect(ranges[0].start).to eq(500)
    expect(ranges[0].finish).to eq(999)
    expect(ranges[0].length).to eq(500)

  it "resolves a suffix range to the final N bytes" ->
    ranges = ByteRange.resolve("bytes=-500", 1000)
    expect(ranges[0].start).to eq(500)
    expect(ranges[0].finish).to eq(999)

  it "clamps a suffix larger than the resource to the whole resource" ->
    ranges = ByteRange.resolve("bytes=-5000", 1000)
    expect(ranges[0].start).to eq(0)
    expect(ranges[0].finish).to eq(999)
    expect(ranges[0].length).to eq(1000)

  it "treats a zero-length suffix as unsatisfiable" ->
    expect(ByteRange.resolve("bytes=-0", 1000)).to eq(:unsatisfiable)

  it "is unsatisfiable when first-byte-pos is past the end" ->
    expect(ByteRange.resolve("bytes=2000-2500", 1000)).to eq(:unsatisfiable)

  it "keeps only the satisfiable ranges of a partial set" ->
    ranges = ByteRange.resolve("bytes=0-99,5000-6000", 1000)
    expect(ranges.size).to eq(1)
    expect(ranges[0].finish).to eq(99)

  it "is unsatisfiable when every range is out of bounds" ->
    expect(ByteRange.resolve("bytes=2000-,3000-4000", 1000)).to eq(:unsatisfiable)

  it "is unsatisfiable against a zero-length resource" ->
    expect(ByteRange.resolve("bytes=0-0", 0)).to eq(:unsatisfiable)

  it "resolves multiple satisfiable ranges in request order" ->
    ranges = ByteRange.resolve("bytes=0-0,-1", 200)
    expect(ranges.size).to eq(2)
    expect(ranges[0].start).to eq(0)
    expect(ranges[0].finish).to eq(0)
    expect(ranges[1].start).to eq(199)
    expect(ranges[1].finish).to eq(199)

describe "ByteRange#content_range" ->
  it "renders the bytes start-finish/total header value" ->
    ranges = ByteRange.resolve("bytes=0-499", 1234)
    expect(ranges[0].content_range).to eq("bytes 0-499/1234")

  it "renders the resolved offsets, not the requested ones" ->
    ranges = ByteRange.resolve("bytes=-100", 1000)
    expect(ranges[0].content_range).to eq("bytes 900-999/1000")

describe "Request#range_header" ->
  it "returns the raw Range header of a parsed request" ->
    req = Request.parse("GET /f HTTP/1.1\r\nRange: bytes=0-499\r\n\r\n")
    expect(req.range_header).to eq("bytes=0-499")

  it "is nil when the request has no Range header" ->
    req = Request.parse("GET /f HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.range_header).to be_nil

describe "Request#ranges" ->
  it "resolves the request's Range header against a total length" ->
    req = Request.parse("GET /f HTTP/1.1\r\nRange: bytes=100-199\r\n\r\n")
    ranges = req.ranges(1000)
    expect(ranges.size).to eq(1)
    expect(ranges[0].start).to eq(100)
    expect(ranges[0].finish).to eq(199)

  it "is nil when the request carries no Range header" ->
    req = Request.parse("GET /f HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.ranges(1000)).to be_nil

  it "surfaces an unsatisfiable range-set" ->
    req = Request.parse("GET /f HTTP/1.1\r\nRange: bytes=5000-6000\r\n\r\n")
    expect(req.ranges(1000)).to eq(:unsatisfiable)

spec_summary
