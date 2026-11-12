# Parity of the benchmark statistics (lib/metaflip/bench) with the independent
# Python reference (spec/bench_stats_reference.py): every record of
# spec/fixtures/bench/stats_cases.tsv is recomputed and compared. Integers and
# strings must agree exactly, floats to 1e-12 relative. Prints FAIL lines and
# exits 1 on a mismatch, else PASS with the number of checks.
use core/file
use ../lib/metaflip/bench/stats
use ../lib/metaflip/bench/format
use ../lib/metaflip/bench/sample
use ../lib/metaflip/bench/profile

# A decimal number of the fixture (Python repr: sign, digits, point, exponent).
-> parse_number(text) (String) f64
  i = 0 ## i64
  negative = false
  if text.starts_with?("-")
    negative = true
    i = 1
  mantissa = 0 ## i64
  fraction = 0 ## i64
  after_point = false
  while i < text.size && text.byte_at(i) != 101
    digit = text.byte_at(i) - 48 ## i64
    if text.byte_at(i) == 46
      after_point = true
    else
      mantissa = mantissa * 10 + digit
      fraction += 1 if after_point
    i += 1
  exponent = 0 ## i64
  if i < text.size
    exponent = text.slice(i + 1, text.size - i - 1).to_i
  shift = exponent - fraction ## i64
  value = mantissa.to_f ## f64
  if shift > 0
    value = value * Math.pow(10.0, shift.to_f)
  elsif shift < 0
    value = value / Math.pow(10.0, (0 - shift).to_f)
  return 0.0 - value if negative
  value

# A float, `inf` or `none` (nil).
-> parse_value(text)
  return nil if text == "none"
  return Stats.inf() if text == "inf"
  parse_number(text)

-> close_numbers(got, want) (f64 f64) bool
  inf = Stats.inf() ## f64
  return got == want if got == inf || want == inf
  scale = Math.abs(want) ## f64
  scale = 1.0 if scale < 1.0
  Math.abs(got - want) <= 0.000000000001 * scale

-> close(got, want)
  return false if got == nil || want == nil
  close_numbers(got, want)

# Reads the fixture and checks each record against the library.
+ Fixture
  ro :checks, :failures

  -> new
    @checks = 0
    @failures = 0
    @samples = {}
    @sample = nil
    @line = 0
    @survival = nil
    @steps = 0
    @rows = nil
    @row = 0
    @comparison = nil
    @table = []
    @profile = nil

  -> expect(ok, label, got, want)
    @checks += 1
    if !ok
      @failures += 1
      << "FAIL line " + @line.to_s + " " + label + ": got " + got.to_s + " want " + want.to_s

  -> expect_float(label, got, want_text)
    want = parse_value(want_text)
    ok = want == nil ? got == nil : close(got, want)
    self.expect(ok, label, got, want_text)

  -> expect_equal(label, got, want)
    self.expect(got == want, label, got, want)

  # Trace field "t:rank;t:rank" as [times, ranks], or nil for "-".
  -> parse_trace(text)
    return nil if text == "-"
    pairs = text.split(";")
    times = f64[pairs.size]
    ranks = f64[pairs.size]
    i = 0 ## i64
    while i < pairs.size
      parts = pairs[i].split(":")
      times[i] = parse_number(parts[0])
      ranks[i] = parse_number(parts[1])
      i += 1
    [times, ranks]

  -> count_field(text)
    text == "-" ? nil : text.to_i

  # One line of the fixture.
  -> feed(line, number)
    @line = number
    return nil if line == "" || line.starts_with?("#")
    f = line.split("\t")
    tag = f[0]
    if tag == "W"
      w = Stats.wilson(f[1].to_i, f[2].to_i)
      self.expect_float("wilson lo " + f[1] + "/" + f[2], w.lo, f[3])
      self.expect_float("wilson hi " + f[1] + "/" + f[2], w.hi, f[4])
    elsif tag == "Q"
      values = f64[f[3].split(",").size]
      f[3].split(",").each_with_index -> (v, i)
        values[i] = parse_number(v)
      self.expect_float("quantile " + f[1] + " of " + f[2], Stats.quantile(values.sort, parse_number(f[1])), f[4])
    elsif tag == "L"
      cell = Stats.generator(f[1].to_i)
      f[2].split(",").each_with_index -> (v, i)
        self.expect_equal("lcg " + f[1] + " #" + i.to_s, Stats.draw(cell), v.to_i)
    elsif tag == "IX"
      cell = Stats.generator(f[1].to_i)
      f[3].split(",").each_with_index -> (v, i)
        self.expect_equal("index " + f[1] + " #" + i.to_s, Stats.pick(cell, f[2].to_i), v.to_i)
    elsif tag == "H"
      self.expect_equal("fnv seed " + f[1], Stats.seed_of(f[1].replace("\\t", "\t")), f[2].to_i)
    elsif tag == "HF"
      raw = Stats.fnv1a(f[1].replace("\\t", "\t"))
      hex = Format.hex32((raw >> 32) & 4294967295) + Format.hex32(raw & 4294967295)
      self.expect_equal("fnv raw " + f[1], hex, f[2])
    elsif tag == "F"
      self.expect_equal("fixed " + f[1] + " " + f[2], Format.fixed(parse_number(f[1]), f[2].to_i), f[3])
    elsif tag == "T"
      self.expect_equal("thousands " + f[1], Format.thousands_tex(f[1].to_i), f[2])
    elsif tag == "CASE"
      @sample = Sample.new(parse_number(f[3]), f[4].to_i, f[5].to_i, 1000)
      @samples[f[1]] = @sample
    elsif tag == "R"
      trace = self.parse_trace(f[6])
      times = trace == nil ? nil : trace[0]
      ranks = trace == nil ? nil : trace[1]
      @sample.add(f[1] == "1", parse_number(f[2]), self.count_field(f[3]), self.count_field(f[4]), self.count_field(f[5]), times, ranks)
    elsif tag == "E"
      self.expect_float("ert " + f[1], @sample.ert(f[1]), f[2])
    elsif tag == "BE"
      interval = @sample.ert_interval(f[1], f[2].to_i, f[3].to_i)
      self.expect_float("bootstrap lo " + f[1], interval.lo, f[4])
      self.expect_float("bootstrap hi " + f[1], interval.hi, f[5])
    elsif tag == "KM"
      @survival = @sample.survival
      @steps = 0
    elsif tag == "KMS"
      self.expect_float("km time #" + @steps.to_s, @survival.times[@steps], f[1])
      self.expect_float("km level #" + @steps.to_s, @survival.levels[@steps], f[2])
      @steps += 1
    elsif tag == "KMT"
      self.expect_equal("km steps", @survival.times.size, @steps) if f[1] == "25"
      self.expect_float("km T" + f[1], @survival.quantile_time(f[1].to_i), f[2])
    elsif tag == "DG"
      @rows = @sample.descent(f[1].to_i, f[2].to_i)
      @row = 0
    elsif tag == "DGR"
      row = @rows[@row]
      self.expect_float("descent time #" + @row.to_s, row[0], f[1])
      self.expect_float("descent q25 #" + @row.to_s, row[1], f[2])
      self.expect_float("descent q50 #" + @row.to_s, row[2], f[3])
      self.expect_float("descent q75 #" + @row.to_s, row[3], f[4])
      @row += 1
    elsif tag == "AUC"
      self.expect_float("auc", @sample.auc, f[1])
    elsif tag == "TH"
      self.expect_float("throughput " + f[1], @sample.throughput(f[1]), f[2])
    elsif tag == "PAIR"
      @comparison = Comparison.of(@samples[f[1]], @samples[f[2]], f[3].to_i, f[4].to_i)
    elsif tag == "PR"
      c = @comparison
      self.expect_float("ratio", c.ratio, f[1])
      self.expect_equal("ratio kept", c.kept, f[4].to_i)
      self.expect_float("ratio lo", c.ratio_interval == nil ? nil : c.ratio_interval.lo, f[2])
      self.expect_float("ratio hi", c.ratio_interval == nil ? nil : c.ratio_interval.hi, f[3])
    elsif tag == "PD"
      c = @comparison
      self.expect_float("difference", c.difference, f[1])
      self.expect_float("difference lo", c.difference_interval.lo, f[2])
      self.expect_float("difference hi", c.difference_interval.hi, f[3])
    elsif tag == "PP"
      @table = []
      @profile = nil
    elsif tag == "PPT"
      @table.push([f[1], f[2], parse_value(f[3])])
    elsif tag == "PPO" || tag == "PPS" || tag == "GM"
      self.profile_record(tag, f)

  # The profile table read so far, built on the first expectation line.
  -> profile_of
    if @profile == nil
      tasks = []
      algos = []
      erts = {}
      @table.each -> (entry)
        tasks.push(entry[0]) if !tasks.include?(entry[0])
        algos.push(entry[1]) if !algos.include?(entry[1])
        erts[entry[0]] = {} if !erts.key?(entry[0])
        erts[entry[0]][entry[1]] = entry[2]
      @profile = Profile.new(tasks, algos, erts)
    @profile

  -> profile_record(tag, f)
    profile = self.profile_of
    if tag == "PPO"
      self.expect_float("profile rho(1) " + f[1], profile.rho(f[1], 1.0), f[2])
      self.expect_equal("profile tasks " + f[1], profile.included.size, f[3].to_i)
    elsif tag == "PPS"
      steps = profile.steps(f[1])
      want = f[2] == "-" ? [] : f[2].split(";")
      self.expect_equal("profile steps " + f[1], steps.size, want.size)
      want.each_with_index -> (pair, i)
        if i < steps.size
          parts = pair.split(":")
          self.expect_float("profile tau " + f[1] + " #" + i.to_s, steps[i][0], parts[0])
          self.expect_float("profile rho " + f[1] + " #" + i.to_s, steps[i][1], parts[1])
    else
      g = profile.geomean(f[1], f[2])
      self.expect_float("geometric mean " + f[1] + "/" + f[2], g[0], f[3])
      self.expect_equal("geometric mean tasks " + f[1] + "/" + f[2], g[1], f[4].to_i)

path = __DIR__ + "/fixtures/bench/stats_cases.tsv"
text = read_file(path)
if text == nil
  << "FAIL cannot read " + path
  exit(1)
fixture = Fixture.new
text.split("\n").each_with_index -> (line, i)
  fixture.feed(line, i + 1)
if fixture.failures > 0
  << "FAIL " + fixture.failures.to_s + " of " + fixture.checks.to_s + " statistics checks"
  exit(1)
<< "PASS bench statistics: " + fixture.checks.to_s + " checks agree with the Python reference"
