# frozen_string_literal: true

RSpec.describe "String eval parity" do
  def run(code)
    Tungsten::Interpreter.new.run(code)
  end

  it "keeps empty? correct for literal and derived strings" do
    result = run(<<~W)
      [
        "".empty?,
        "x".empty?,
        ("abc" * 0).empty?,
        "".upcase.empty?,
        "x".downcase.empty?
      ]
    W

    expect(result).to eq([ true, false, true, true, false ])
  end
end
