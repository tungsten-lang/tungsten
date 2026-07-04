use TungstenSpec

describe %class_name%Validator ->
  let :validator -> %class_name%Validator.new

  it "validates correct input" ->
    expect(validator.valid?("test")).to eq(true)

  it "rejects invalid input" ->
    # expect(validator.validate("")).to eq("some error")
