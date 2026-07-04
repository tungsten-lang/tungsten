# Regression coverage for the wit `?` polynomial-plot scrub (the in-line redraw).
#
# The scrub redraws a multi-line plot in place by moving the cursor up over the
# previous frame and clearing. Two ways that has gone wrong:
#   * a frame taller than the terminal scrolls, so the relative move-up clamps
#     and the previous frame can't be fully overwritten — leftover plots;
#   * a *repeat* scrub session computes its first move-up from the original
#     `? …` plot height, but the on-screen plot is now the previous scrub's
#     render (taller once zeroes/complex lines appeared) — leftover `scrub>`
#     headers, one per session.
#
# Both show up as duplicated content. We can't eyeball a real terminal in CI, so
# we drive a real `bin/wit` in a PTY and reconstruct the visible screen with a
# small fixed-height, scrolling VT emulator. The invariant the user wants:
# after scrubbing — once or many times — the screen holds exactly ONE plot.
#
# PTY + the compiled drawille bit make this slow/environment-dependent, so it
# lives in the `expensive` suite and skips cleanly when the bit isn't built.

require "pty"
require "io/console"
require "timeout"

# Feed it the raw bytes a program writes to a terminal; read back the visible
# screen. Models exactly the operations the scrub relies on: cursor up/down
# (clamped), carriage return, line feed (with scroll at the bottom), and the
# "clear to end of screen" / "clear line" erases. A redraw that miscounts and
# fails to overwrite its previous frame therefore reconstructs as duplicates.
class ScrubVT
  def initialize(rows, cols)
    @rows = rows
    @cols = cols
    @screen = Array.new(rows) { +"" }
    @row = 0
    @col = 0
  end

  def feed(bytes)
    s = bytes.dup.force_encoding("UTF-8")
    i = 0
    while i < s.length
      ch = s[i]
      if ch == "\e" && s[i + 1] == "["
        if (pm = s[(i + 1)..].match(/\A\[\?[\d;]*[A-Za-z]/)) # private mode, e.g. ?1049h
          i += 1 + pm[0].length
          next
        end
        m = s[(i + 1)..].match(/\A\[([\d;]*)([A-Za-z])/)
        if m.nil?
          i += 2
          next
        end
        n = m[1].split(";").first.to_s.then { |x| x.empty? ? 1 : x.to_i }
        csi(m[2], n)
        i += 1 + m[0].length
      elsif ch == "\e"
        i += 2 # other escape (e.g. DECSC/DECRC) — ignored for our purposes
      elsif ch == "\n"
        line_feed
        i += 1
      elsif ch == "\r"
        @col = 0
        i += 1
      else
        put(ch)
        i += 1
      end
    end
    self
  end

  # The visible screen, ANSI colour stripped, right-trimmed.
  def text
    @screen.map { |l| l.gsub(/\e\[[0-9;]*m/, "").rstrip }.join("\n")
  end

  private

  def csi(cmd, n)
    case cmd
    when "A" then @row = [ @row - n, 0 ].max
    when "B" then @row = [ @row + n, @rows - 1 ].min
    when "C" then @col += n
    when "D" then @col = [ @col - n, 0 ].max
    when "H" then (@row = 0; @col = 0)
    when "J" # clear from cursor to end of screen
      @screen[@row] = @screen[@row][0, @col].to_s.ljust(@col)
      ((@row + 1)...@rows).each { |r| @screen[r] = +"" }
    when "K" # clear from cursor to end of line
      @screen[@row] = @screen[@row][0, @col].to_s
    end
  end

  def line_feed
    @row += 1
    return if @row < @rows

    @screen.shift
    @screen.push(+"")
    @row = @rows - 1
  end

  def put(ch)
    @screen[@row] = @screen[@row].ljust(@col) if @screen[@row].length < @col
    @screen[@row] = @screen[@row][0, @col].to_s + ch + @screen[@row][(@col + 1)..].to_s
    @col += 1
  end
end

RSpec.describe "wit `?` plot scrub" do
  repo_root = File.expand_path("../../..", __dir__)
  wit_bin = File.join(repo_root, "bin", "wit")
  drawille_bin = File.join(repo_root, "bits", "tungsten-drawille", "bin", "drawille")

  # x-axis rows look like `----+----…----+----`; the prompt/separator rules use
  # box-drawing `─`, so this only counts plot axes.
  axes = ->(screen) { screen.scan(/-{2,}\+-{2,}/).length }
  headers = ->(screen) { screen.scan(/scrub>/).length }
  # The Argand plane has no `----+----` x-axis; its one-per-render marker is the
  # `z = …` annotation line, so counting those counts visible complex planes.
  zlines = ->(screen) { screen.scan(/z = /).length }

  # Drive a real wit PTY session. The block gets (writer, wait) where `wait`
  # blocks until a marker shows up in the output (robust against compile/render
  # latency); returns the reconstructed visible screen.
  def run_wit(wit_bin, rows: 40, cols: 130)
    raw = +""
    vt = ScrubVT.new(rows, cols)
    PTY.spawn({ "TERM" => "xterm" }, wit_bin) do |r, w, pid|
      begin
        r.winsize = [ rows, cols ]
      rescue StandardError
        nil
      end
      reader = Thread.new do
        loop { raw << r.readpartial(4096) }
      rescue StandardError
        nil
      end
      wait = lambda do |marker, timeout = 15|
        bytes = marker.b # raw is BINARY; compare in bytes so UTF-8 markers (∫) work
        deadline = Time.now + timeout
        sleep 0.02 while !raw.include?(bytes) && Time.now < deadline
        raise "timed out waiting for #{marker.inspect}" unless raw.include?(bytes)
      end
      begin
        wait.call("? inspect") # the prompt hint — `wit>` isn't contiguous (Reline splits it with escapes)
        yield(w, wait)
      ensure
        reader.kill
        Process.kill("TERM", pid) rescue nil
      end
    end
    vt.feed(raw).text
  end

  before do
    skip "drawille bit not built (#{drawille_bin}) — run bin/tungsten compile" unless File.executable?(drawille_bin)
  end

  it "leaves exactly one plot after a single scrub session" do
    screen = run_wit(wit_bin) do |w, wait|
      w.write("? -5..5/∫(5x² - 3x + 1)\r")
      wait.call("∫ =") # the integral line prints once the plot is rendered
      w.write("\r")
      wait.call("scrub>")
      4.times { w.write("\e[B"); sleep 0.25 } # scrub the constant down (flips complex→real)
      sleep 0.4
      w.write("q\r")
      sleep 0.4
    end

    expect(headers.call(screen)).to eq(1)
    expect(axes.call(screen)).to eq(1)
  end

  it "leaves exactly one plot after repeated scrub sessions" do
    screen = run_wit(wit_bin) do |w, wait|
      w.write("? -5..5/∫(5x² - 3x + 1)\r")
      wait.call("∫ =")
      3.times do
        w.write("\r")          # blank Enter re-enters the scrub on the prior plot
        sleep 0.6
        3.times { w.write("\e[B"); sleep 0.2 }
        w.write("q")           # exit this session
        sleep 0.5
      end
    end

    expect(headers.call(screen)).to eq(1)
    expect(axes.call(screen)).to eq(1)
    # no stacked blank prompts left behind by the sessions
    expect(screen).not_to match(/^wit>\s*\n\s*\nwit>\s*$/)
  end

  # ── Complex-number Argand viz (`? 3+4i`, `? (1+i)*(2+3i)`) ──────────────
  # Same VT-reconstruction invariant: after rendering (and scrubbing) the
  # screen holds exactly ONE Argand plane. The |z|/arg/rotate numbers are all
  # computed in compiled Tungsten Complex<f64> by the bit, so this also guards
  # the dogfooded math end-to-end.

  it "renders a single complex value with |z| and arg" do
    screen = run_wit(wit_bin) do |_w, wait|
      _w.write("? 3+4i\r")
      wait.call("arg =", 20)
      sleep 0.4
    end
    expect(zlines.call(screen)).to eq(1)
    expect(screen).to include("z = 3+4i")
    expect(screen).to include("|z| = 5")
    expect(screen).to include("arg = 53.13°")
  end

  it "renders a product as multiply-as-rotation with the rotate/scale read-out" do
    screen = run_wit(wit_bin) do |w, wait|
      w.write("? (1+i)*(2+3i)\r")
      wait.call("rotate", 20)
      sleep 0.4
    end
    expect(zlines.call(screen)).to eq(1)
    expect(screen).to include("z = -1+5i")            # (1+i)(2+3i) = -1+5i, in Tungsten
    expect(screen).to include("rotate +56.31°")       # arg(2+3i)
    expect(screen).to include("scale ×3.606")         # |2+3i|
  end

  it "leaves exactly one plane after a complex scrub session" do
    screen = run_wit(wit_bin) do |w, wait|
      w.write("? 3+4i\r")
      wait.call("arg =", 20)
      w.write("\r")                                    # blank Enter → scrub
      wait.call("scrub>", 20)
      3.times { w.write("\e[A"); sleep 0.25 }          # nudge the imaginary coeff up
      sleep 0.4
      w.write("q\r")
      sleep 0.4
    end
    expect(headers.call(screen)).to eq(1)
    expect(zlines.call(screen)).to eq(1)
    expect(screen).to include("z = 3+7i")              # 4 → 7 after three ↑ nudges
  end

  it "leaves exactly one plane after repeated complex scrub sessions" do
    screen = run_wit(wit_bin) do |w, wait|
      w.write("? 3+4i\r")
      wait.call("arg =", 20)
      3.times do
        w.write("\r")
        sleep 0.6
        2.times { w.write("\e[A"); sleep 0.2 }
        w.write("q")
        sleep 0.5
      end
    end
    expect(headers.call(screen)).to eq(1)
    expect(zlines.call(screen)).to eq(1)
  end

  it "rotates the input via the arg knob (multiply-as-rotation), |z| preserved" do
    screen = run_wit(wit_bin) do |w, wait|
      w.write("? 3+4i\r")
      wait.call("arg =", 20)
      w.write("\r")                                     # blank Enter → scrub (cursor on last digit)
      wait.call("scrub>", 20)
      w.write("\e[C")                                   # → to the rotation knob
      sleep 0.3
      10.times { w.write("\e[A"); sleep 0.12 }          # rotate +10°
      sleep 0.4
      w.write("q\r")
      sleep 0.4
    end
    expect(headers.call(screen)).to eq(1)
    expect(zlines.call(screen)).to eq(1)
    expect(screen).to include("arg = 63.13°")           # 53.13° + 10° rotation
    expect(screen).to include("|z| = 5")                # modulus preserved through rotation
    expect(screen).to match(/z = 2\.2\d+\+4\.4\d+i/)    # 5∠63.13° ≈ 2.26+4.46i
  end

  it "resumes a complex scrub on the field last left (the angle knob)" do
    screen = run_wit(wit_bin) do |w, wait|
      w.write("? 3+4i\r")
      wait.call("arg =", 20)
      # Session 1: move to the rotation knob and quit (the field is remembered).
      w.write("\r")
      wait.call("scrub>", 20)
      w.write("\e[C")                                   # → angle knob
      sleep 0.3
      w.write("q")
      sleep 0.4
      # Session 2: blank-Enter resumes ON the knob, so ↑ rotates (not digit-edits).
      w.write("\r")
      sleep 0.6
      3.times { w.write("\e[A"); sleep 0.15 }
      sleep 0.3
      w.write("q\r")
      sleep 0.4
    end
    # Rotated by +3° (resumed on the knob); the input digits are untouched.
    expect(screen).to include("arg = 56.13°")           # 53.13° + 3°
    expect(screen).to include("? 3+4i")                 # components unchanged → was NOT on a digit
    expect(headers.call(screen)).to eq(1)
  end
end
