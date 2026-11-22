RSpec.describe "rescuing errors raised natively by Ruby-backed builtins" do
  def run(code)
    Tungsten::Interpreter.new.run(code)
  end

  def rescued(expr)
    run(<<~W)
      begin
        #{expr}
        "not raised"
      rescue e
        [e.class.name, e.message]
    W
  end

  it "rescues Array#insert's IndexError as Core IndexError with Ruby's message" do
    expect(rescued("[1, 2].insert(-4, 0)")).to eq([ "IndexError", "index -4 too small for array; minimum: -3" ])
  end

  it "maps native exception classes to the matching Core error class" do
    expect(rescued("{a: 1}.fetch(:b)")[0]).to eq("KeyError")
    expect(rescued("\"abc\".center(1, \"\")")).to eq([ "ArgumentError", "zero width padding" ])
    expect(rescued("[1, 2].fetch(9)")[0]).to eq("IndexError")
    expect(rescued("1 / 0")).to eq([ "ZeroDivisionError", "division by zero" ])
  end

  it "keeps running after the rescue" do
    result = run(<<~W)
      out = []
      begin
        [1, 2].insert(-4, 0)
      rescue e
        out.push("caught " + e.to_s)
      out.push("after")
      out
    W

    expect(result).to eq([ "caught index -4 too small for array; minimum: -3", "after" ])
  end

  it "does not swallow break, next, or return unwinding through a begin" do
    result = run(<<~W)
      -> first_big(xs)
        xs.each ->(x)
          begin
            return x if x > 2
          rescue e
            return -1
        0

      seen = []
      [1, 2, 3, 4].each ->(x)
        begin
          next if x == 2
          break if x == 4
          seen.push(x)
        rescue e
          seen.push("rescued")
      out = [first_big([1, 3, 5]), seen]
      out
    W

    expect(result).to eq([ 3, [ 1, 3 ] ])
  end

  it "raises a rescuable ArgumentError for a surplus argument to first/last, like the compiled engine" do
    message = "'first' takes 0 arguments, got 1 — arguments are never silently dropped or padded"
    expect(rescued("[1, 2].first(-1)")).to eq([ "ArgumentError", message ])
    expect(rescued("[1, 2].last(1)")[0]).to eq("ArgumentError")
    expect { run("[1, 2].first(-1)") }.to raise_error(Tungsten::Error, message)
    expect(run("[1, 2].first")).to eq(1)
  end
end
