# Language sugar ported from the compiled self-hosted compiler:
#   1. trailing ro/rw accessor marker on @-binding methods
#   2. constructor-call sugar — Point(3, 4) ≡ Point.new(3, 4)
#   3. implicit construction from the receiver class — a one-param method
#      called with N>1 args wraps them in receiver.class.new(...)
RSpec.describe "language sugar" do
  def run(code)
    Tungsten::Interpreter.new.run(code)
  end

  def output(code)
    capture(:stdout) { run(code) }.chomp
  end

  def capture(stream)
    stream = stream.to_s
    captured = StringIO.new
    previous = $stdout

    $stdout = captured if stream == "stdout"

    yield
    captured.string
  ensure
    $stdout = previous if stream == "stdout"
  end

  describe "trailing ro/rw accessor marker" do
    it "generates readers for @-bound params marked ro" do
      expect(output(<<~CODE)).to eq("3\n4")
        + Point
          -> new(@x, @y) ro

        p = Point.new(3, 4)
        << p.x
        << p.y
      CODE
    end

    it "generates readers and writers for @-bound params marked rw" do
      expect(output(<<~CODE)).to eq("10\n2")
        + Vec
          -> new(@a, @b) rw

        v = Vec.new(1, 2)
        v.a = 10
        << v.a
        << v.b
      CODE
    end

    it "does not generate writers for ro" do
      expect do
        run(<<~CODE)
          + Point
            -> new(@x, @y) ro

          p = Point.new(3, 4)
          p.x = 9
        CODE
      end.to raise_error(Tungsten::Error)
    end

    it "strips the marker from an indented body" do
      expect(output(<<~CODE)).to eq("built\n5")
        + Tagged
          -> new(@v)
            ro
            << "built"

        t = Tagged.new(5)
        << t.v
      CODE
    end

    it "leaves a hand-written reader in place" do
      expect(output(<<~CODE)).to eq("6")
        + Point
          -> new(@x) ro

          -> x
            @x * 2

        << Point.new(3).x
      CODE
    end

    it "still binds ivars for inline bodies without a marker" do
      expect(output(<<~CODE)).to eq("3")
        + Point
          -> new(@x, @y) 99

          ro :x

        << Point.new(3, 4).x
      CODE
    end
  end

  describe "constructor-call sugar" do
    it "treats ClassName(args) as ClassName.new(args)" do
      expect(output(<<~CODE)).to eq("3")
        + Point
          -> new(@x, @y) ro

        << Point(3, 4).x
      CODE
    end

    it "constructs assignable instances" do
      expect(output(<<~CODE)).to eq("4")
        + Point
          -> new(@x, @y) ro

        p = Point(3, 4)
        << p.y
      CODE
    end
  end

  describe "implicit construction from the receiver class" do
    it "wraps N>1 args to a one-param method in receiver.class.new" do
      expect(output(<<~CODE)).to eq("5.0")
        + Point
          -> new(@x, @y) ro

          -> distance(other)
            dx = (@x - other.x).to_f
            dy = (@y - other.y).to_f
            Math.sqrt(dx * dx + dy * dy)

        p = Point(3, 4)
        << p.distance(0, 0)
      CODE
    end

    it "matches the explicit construction" do
      code = <<~CODE
        + Point
          -> new(@x, @y, @z) ro

          -> distance(other)
            dx = (@x - other.x).to_f
            dy = (@y - other.y).to_f
            dz = (@z - other.z).to_f
            Math.sqrt(dx * dx + dy * dy + dz * dz)

        p = Point(3, 4, 5)
        << p.distance(2, 3, 4)
        << p.distance(Point(2, 3, 4))
      CODE
      lines = output(code).split("\n")
      expect(lines[0]).to eq(lines[1])
      expect(lines[0].to_f).to be_within(1e-9).of(Math.sqrt(3))
    end

    it "does not fire when the constructor arity differs" do
      expect do
        run(<<~CODE)
          + Point
            -> new(@x, @y) ro

            -> distance(other)
              @x - other.x

          p = Point(3, 4)
          p.distance(1, 2, 3)
        CODE
      end.to raise_error(Tungsten::Error)
    end

    it "does not fire for multi-param methods" do
      expect(output(<<~CODE)).to eq("7")
        + Point
          -> new(@x, @y) ro

          -> sum2(a, b)
            a + b

        p = Point(3, 4)
        << p.sum2(3, 4)
      CODE
    end
  end

  describe "full acceptance program" do
    it "runs the Point distance example" do
      lines = output(<<~CODE).split("\n")
        + Point
          -> new(@x, @y, @z) ro

          -> distance(other)
            dx = (@x - other.x).to_f
            dy = (@y - other.y).to_f
            dz = (@z - other.z).to_f
            Math.sqrt(dx * dx + dy * dy + dz * dz)

        p = Point(3, 4, 5)
        << p.x
        << p.distance(Point(0, 0, 0))
        << p.distance(2, 3, 4)
      CODE

      expect(lines[0]).to eq("3")
      expect(lines[1].to_f).to be_within(1e-9).of(Math.sqrt(50))
      expect(lines[2].to_f).to be_within(1e-9).of(Math.sqrt(3))
    end
  end
end
