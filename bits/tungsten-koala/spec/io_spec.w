# CSV I/O for DataFrame — string path on both engines.
#
#   bin/tungsten bits/tungsten-koala/spec/io_spec.w

use spec
use koala

describe "DataFrame CSV" ->
  it "round-trips a mixed frame with nils and quoted commas" ->
    df = DataFrame.new([
      [:name, ["Ada", "Bob, Jr", nil]],
      [:age,  [36, 40, 25]],
      [:score, [1.to_f / 2.to_f, 2, 3]]
    ])
    text = df.to_csv_string
    expect(text.include?("name,age,score")).to be_true
    expect(text.include?("\"Bob, Jr\"")).to be_true

    back = DataFrame.from_csv_string(text)
    expect(back != nil).to be_true
    expect(back.row_count).to eq(3)
    expect(back.column_names.map -> (n) n.to_s).to eq(["name", "age", "score"])
    expect(back.column_values(:age)).to eq([36, 40, 25])
    expect(back.column_values(:name)[0]).to eq("Ada")
    expect(back.column_values(:name)[1]).to eq("Bob, Jr")
    expect(back.column_values(:name)[2]).to eq(nil)

  it "returns nil for empty or non-string input" ->
    expect(DataFrame.from_csv_string(nil)).to eq(nil)
    expect(DataFrame.from_csv_string("")).to eq(nil)

spec_summary
