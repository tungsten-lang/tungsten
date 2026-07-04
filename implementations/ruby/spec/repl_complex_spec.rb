# Fast unit coverage for the wit `?` complex-number Argand routing helpers:
# the `i`-discriminated detector, the operand/operator tokenizer (which does NO
# arithmetic — the complex math is all done in Tungsten by the drawille bit),
# and the display formatters. The heavier end-to-end render/scrub lives in the
# PTY suite (repl_plot_scrub_expensive.rb).

RSpec.describe "wit `?` complex-number routing" do
  # The helpers are private instance methods; exercise them on a bare instance.
  let(:repl) { Tungsten::REPL.allocate }
  def call(m, *a) = repl.send(m, *a)

  describe "#looks_like_complex?" do
    it "matches expressions built of complex characters that contain `i`" do
      [ "3+4i", "0.8+0.6i", "(1+i)*(2+3i)", "i", "-2-3i", "4i", "1/i" ].each do |s|
        expect(call(:looks_like_complex?, s)).to be(true), "expected #{s.inspect} to route to complex"
      end
    end

    it "rejects plain numbers, polynomials, and ordinary queries" do
      [ "5", "42", "2x+3", "x*x", "Σ(2x)", "∫(x)", "foo", "pi", "", "  " ].each do |s|
        expect(call(:looks_like_complex?, s)).to be(false), "expected #{s.inspect} NOT to route to complex"
      end
    end
  end

  describe "#tokenize_complex" do
    it "reads a lone complex literal as one factor, no operators" do
      expect(call(:tokenize_complex, "3+4i")).to eq([ [ [ 3.0, 4.0 ] ], [] ])
      expect(call(:tokenize_complex, "0.8+0.6i")).to eq([ [ [ 0.8, 0.6 ] ], [] ])
      expect(call(:tokenize_complex, "-2-3i")).to eq([ [ [ -2.0, -3.0 ] ], [] ])
      expect(call(:tokenize_complex, "4i")).to eq([ [ [ 0.0, 4.0 ] ], [] ])
      expect(call(:tokenize_complex, "i")).to eq([ [ [ 0.0, 1.0 ] ], [] ])
    end

    it "splits products/quotients at the top level, keeping +/- inside literals" do
      expect(call(:tokenize_complex, "(1+i)*(2+3i)")).to eq([ [ [ 1.0, 1.0 ], [ 2.0, 3.0 ] ], [ "*" ] ])
      expect(call(:tokenize_complex, "(1+2i)/(3-i)")).to eq([ [ [ 1.0, 2.0 ], [ 3.0, -1.0 ] ], [ "/" ] ])
    end

    it "returns nil on an unparseable factor" do
      expect(call(:tokenize_complex, "*3i")).to be_nil
      expect(call(:tokenize_complex, "")).to be_nil
    end
  end

  describe "#fmt_complex" do
    it "renders a±bi with the conventional elisions" do
      expect(call(:fmt_complex, 3.0, 4.0)).to eq("3+4i")
      expect(call(:fmt_complex, -1.0, 5.0)).to eq("-1+5i")
      expect(call(:fmt_complex, 0.8, 0.6)).to eq("0.8+0.6i")
      expect(call(:fmt_complex, 2.0, -3.0)).to eq("2-3i")
      expect(call(:fmt_complex, 3.0, 0.0)).to eq("3")    # real only
      expect(call(:fmt_complex, 0.0, 4.0)).to eq("4i")   # imaginary only
      expect(call(:fmt_complex, 0.0, -1.0)).to eq("-i")  # unit imaginary
    end
  end

  describe "#deg" do
    it "converts radians to degrees, trimming a trailing .0" do
      expect(call(:deg, 0.927293)).to eq("53.13")
      expect(call(:deg, 0.785398)).to eq("45")
      expect(call(:deg, 1.768184)).to eq("101.31")
    end
  end

  describe "#complex_annotation" do
    it "shows z/|z|/arg for a single value" do
      recs = [ { role: "z", re: 3.0, im: 4.0, abs: 5.0, arg: 0.927295 } ]
      ann = call(:complex_annotation, [], recs).gsub(/\e\[[0-9;]*m/, "")
      expect(ann).to include("arg = 53.13°   z = 3+4i   |z| = 5")
    end

    it "adds a rotate/scale read-out per multiplier for a product" do
      recs = [
        { role: "operand", re: 1.0, im: 1.0, abs: 1.414214, arg: 0.785398 },
        { role: "operand", re: 2.0, im: 3.0, abs: 3.605551, arg: 0.982794 },
        { role: "result",  re: -1.0, im: 5.0, abs: 5.099020, arg: 1.768193 }
      ]
      ann = call(:complex_annotation, [ "*" ], recs).gsub(/\e\[[0-9;]*m/, "")
      expect(ann).to include("arg = 101.31°   z = -1+5i   |z| = 5.099")
      expect(ann).to include("× (2+3i): rotate +56.31°, scale ×3.606")
    end
  end
end
