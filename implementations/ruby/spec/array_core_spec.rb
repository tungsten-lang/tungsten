RSpec.describe "core array APIs" do
  def run(code)
    Tungsten::Interpreter.new.run(code)
  end

  it "sorts arrays with a stable in-place mergesort" do
    result = run(<<~W)
      records = [[2, "a"], [1, "b"], [2, "c"], [1, "d"]]
      records.mergesort! -> (left, right)
        left[0] - right[0]
      records
    W

    expect(result).to eq([ [ 1, "b" ], [ 1, "d" ], [ 2, "a" ], [ 2, "c" ] ])
  end

  it "returns the array from mergesort!" do
    result = run(<<~W)
      a = [3, 1, 2]
      b = a.mergesort!
      [a, b]
    W

    expect(result).to eq([ [ 1, 2, 3 ], [ 1, 2, 3 ] ])
  end

  it "returns a sorted copy from sort" do
    result = run(<<~W)
      a = [3, 1, 2]
      b = a.sort
      [a, b]
    W

    expect(result).to eq([ [ 3, 1, 2 ], [ 1, 2, 3 ] ])
  end

  it "shuffles through Fisher-Yates without losing elements" do
    result = run(<<~W)
      a = [1, 2, 3, 4]
      b = a.shuffle
      c = a.shuffle!
      [a.sort, b.sort, c.sort]
    W

    expect(result).to eq([ [ 1, 2, 3, 4 ], [ 1, 2, 3, 4 ], [ 1, 2, 3, 4 ] ])
  end

  it "preserves the indexed gather shuffle overload" do
    expect(run("[10, 20, 30].shuffle([2, 0, 2])")).to eq([ 30, 10, 30 ])
  end

  it "supports Ruby-compatible rotate counts" do
    result = run(<<~W)
      [
        [0, 1, 2, 3].rotate,
        [0, 1, 2, 3].rotate(2),
        [0, 1, 2, 3].rotate(6),
        [0, 1, 2, 3].rotate(0),
        [0, 1, 2, 3].rotate(-1),
        [0, 1, 2, 3].rotate(-5),
        [].rotate,
        [1].rotate(99)
      ]
    W

    expect(result).to eq([
      [ 1, 2, 3, 0 ],
      [ 2, 3, 0, 1 ],
      [ 2, 3, 0, 1 ],
      [ 0, 1, 2, 3 ],
      [ 3, 0, 1, 2 ],
      [ 3, 0, 1, 2 ],
      [],
      [ 1 ]
    ])
  end

  it "rotates arrays in place" do
    result = run(<<~W)
      a = [0, 1, 2, 3]
      r = a.rotate!(2)
      [a, r]
    W

    expect(result).to eq([ [ 2, 3, 0, 1 ], [ 2, 3, 0, 1 ] ])
  end

  it "keeps array methods working after Array core autoloads" do
    result = run(<<~W)
      Array
      [
        [3, 1, 2].sort,
        [10, 20, 30].shuffle([2, 0, 2]),
        [0, 1, 2, 3].rotate(2)
      ]
    W

    expect(result).to eq([ [ 1, 2, 3 ], [ 30, 10, 30 ], [ 2, 3, 0, 1 ] ])
  end

  it "keeps block mergesort working after Array core autoloads" do
    result = run(<<~W)
      Array
      records = [[2, "a"], [1, "b"], [2, "c"], [1, "d"]]
      records.mergesort! -> (left, right)
        left[0] - right[0]
      records
    W

    expect(result).to eq([ [ 1, "b" ], [ 1, "d" ], [ 2, "a" ], [ 2, "c" ] ])
  end
end
