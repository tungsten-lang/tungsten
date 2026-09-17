# frozen_string_literal: true

RSpec.describe Tungsten::Date do
  it "parses datetime offsets instead of dropping the clock" do
    nepal = described_class.parse("2024-01-01T12:00:00+05:45")
    expect(nepal.year).to eq(2024)
    expect(nepal.hour).to eq(12)
    expect(nepal.tz).to eq(345)
    expect(nepal.to_s).to eq("2024-01-01T12:00:00+05:45")
  end

  it "rejects offsets that are not a packed 15-minute step" do
    expect { described_class.parse("2024-01-01T12:00:00+00:10") }
      .to raise_error(Tungsten::Error, /15-minute offset/)
  end

  it "accepts Amsterdam +00:20" do
    expect(described_class.parse("1937-07-01T12:00:00+00:20").tz).to eq(20)
  end

  it "does not clamp catch-up days when adding a non-zero day count" do
    d = described_class.parse("1712-02-30")
    expect(d.day).to eq(30)
    expect((d + 0).day).to eq(30)
    expect { d + 1 }.to raise_error(Tungsten::Error, "calendar context required")
  end

  it "builds a Gregorian ordinal without wrapping February" do
    d = described_class.ordinal(1867, 250)
    expect([d.year, d.month, d.day]).to eq([1867, 9, 7])
  end

  it "constructs from year, month, day without wrapping" do
    d = described_class.new(2024, 1, 1)
    expect([d.year, d.month, d.day]).to eq([2024, 1, 1])
    expect(d.to_s).to eq("2024-01-01T00:00:00Z")
  end

  it "defaults month and day when only a year is given" do
    d = described_class.new(2024)
    expect([d.year, d.month, d.day]).to eq([2024, 1, 1])
  end
end
