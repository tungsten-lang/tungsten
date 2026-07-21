# Forge HTTP-date specs — HttpDate (RFC 7231 §7.1.1.1 parsing across all
# three historical formats and IMF-fixdate formatting). Before HttpDate the
# request/response surface could not compare two timestamps or stamp a Date
# header, so conditional requests (304 Not Modified) were impossible; it is
# the time counterpart to the ByteRange / Negotiation / Forwarded parsers.
#
# Pure: no clock and no I/O, so every example runs identically under the
# interpreter and compiled. The canonical instant throughout is
# 1994-11-06 08:49:37 GMT = 784111777 seconds since the Unix epoch (the
# example RFC 7231 §7.1.1.1 itself uses).

use spec_helper

describe "HttpDate.parse (IMF-fixdate)" ->
  it "parses the modern format to epoch seconds" ->
    expect(HttpDate.parse("Sun, 06 Nov 1994 08:49:37 GMT")).to eq(784111777)

  it "parses the Unix epoch itself" ->
    expect(HttpDate.parse("Thu, 01 Jan 1970 00:00:00 GMT")).to eq(0)

  it "parses a post-2000 date" ->
    expect(HttpDate.parse("Wed, 21 Oct 2015 07:28:00 GMT")).to eq(1445412480)

  it "accepts a UTC zone token as well as GMT" ->
    expect(HttpDate.parse("Sun, 06 Nov 1994 08:49:37 UTC")).to eq(784111777)

  it "tolerates surrounding whitespace" ->
    expect(HttpDate.parse("  Sun, 06 Nov 1994 08:49:37 GMT  ")).to eq(784111777)

describe "HttpDate.parse (RFC 850)" ->
  it "parses the obsolete full-day dashed format" ->
    expect(HttpDate.parse("Sunday, 06-Nov-94 08:49:37 GMT")).to eq(784111777)

  it "expands a 2-digit year 0-69 into the 2000s" ->
    expect(HttpDate.parse("Sunday, 06-Nov-37 00:00:00 GMT")).to eq(HttpDate.parse("Sat, 06 Nov 2037 00:00:00 GMT"))

  it "expands a 2-digit year 70-99 into the 1900s" ->
    expect(HttpDate.parse("Friday, 06-Nov-70 00:00:00 GMT")).to eq(HttpDate.parse("Fri, 06 Nov 1970 00:00:00 GMT"))

describe "HttpDate.parse (asctime)" ->
  it "parses the zone-less C library format" ->
    expect(HttpDate.parse("Sun Nov  6 08:49:37 1994")).to eq(784111777)

  it "collapses the double space before a single-digit day" ->
    expect(HttpDate.parse("Sun Nov  6 08:49:37 1994")).to eq(HttpDate.parse("Sun, 06 Nov 1994 08:49:37 GMT"))

describe "HttpDate.parse (all three formats name one instant)" ->
  it "agrees across IMF-fixdate, RFC 850 and asctime" ->
    imf  = HttpDate.parse("Sun, 06 Nov 1994 08:49:37 GMT")
    r850 = HttpDate.parse("Sunday, 06-Nov-94 08:49:37 GMT")
    asc  = HttpDate.parse("Sun Nov  6 08:49:37 1994")
    expect(imf).to eq(r850)
    expect(r850).to eq(asc)

describe "HttpDate.parse (rejection)" ->
  it "is nil for nil or empty input" ->
    expect(HttpDate.parse(nil)).to be_nil
    expect(HttpDate.parse("")).to be_nil

  it "is nil for unstructured text" ->
    expect(HttpDate.parse("not a date")).to be_nil

  it "is nil for a non-GMT zone" ->
    expect(HttpDate.parse("Sun, 06 Nov 1994 08:49:37 EST")).to be_nil

  it "is nil for an unknown month name" ->
    expect(HttpDate.parse("Sun, 06 Xxx 1994 08:49:37 GMT")).to be_nil

  it "is nil for a non-numeric day or year" ->
    expect(HttpDate.parse("Sun, 0x Nov 1994 08:49:37 GMT")).to be_nil
    expect(HttpDate.parse("Sun, 06 Nov 19y4 08:49:37 GMT")).to be_nil

  it "is nil for an out-of-range hour" ->
    expect(HttpDate.parse("Sun, 06 Nov 1994 24:00:00 GMT")).to be_nil

  it "is nil for an out-of-range minute" ->
    expect(HttpDate.parse("Sun, 06 Nov 1994 08:60:00 GMT")).to be_nil

  it "is nil for a malformed time field" ->
    expect(HttpDate.parse("Sun, 06 Nov 1994 08:49 GMT")).to be_nil

  it "is nil for a truncated IMF-fixdate missing its zone" ->
    expect(HttpDate.parse("Sun, 06 Nov 1994 08:49:37")).to be_nil

describe "HttpDate.format" ->
  it "renders epoch seconds as IMF-fixdate" ->
    expect(HttpDate.format(784111777)).to eq("Sun, 06 Nov 1994 08:49:37 GMT")

  it "renders the Unix epoch (a Thursday)" ->
    expect(HttpDate.format(0)).to eq("Thu, 01 Jan 1970 00:00:00 GMT")

  it "renders a post-2000 date" ->
    expect(HttpDate.format(1445412480)).to eq("Wed, 21 Oct 2015 07:28:00 GMT")

  it "zero-pads day, hour, minute and second" ->
    expect(HttpDate.format(0)).to eq("Thu, 01 Jan 1970 00:00:00 GMT")

  it "is nil for a nil or negative epoch" ->
    expect(HttpDate.format(nil)).to be_nil
    expect(HttpDate.format(-1)).to be_nil

describe "HttpDate round-trips" ->
  it "parse(format(e)) recovers the epoch" ->
    expect(HttpDate.parse(HttpDate.format(784111777))).to eq(784111777)
    expect(HttpDate.parse(HttpDate.format(1445412480))).to eq(1445412480)
    expect(HttpDate.parse(HttpDate.format(0))).to eq(0)

  it "format(parse(s)) recanonicalises an RFC 850 date to IMF-fixdate" ->
    expect(HttpDate.format(HttpDate.parse("Sunday, 06-Nov-94 08:49:37 GMT"))).to eq("Sun, 06 Nov 1994 08:49:37 GMT")

  it "renders every month name correctly" ->
    expect(HttpDate.format(HttpDate.parse("Sat, 15 Feb 2020 12:00:00 GMT"))).to eq("Sat, 15 Feb 2020 12:00:00 GMT")
    expect(HttpDate.format(HttpDate.parse("Thu, 31 Dec 2099 23:59:59 GMT"))).to eq("Thu, 31 Dec 2099 23:59:59 GMT")

spec_summary
