use TungstenSpec

describe %class_name%Config ->
  it "loads defaults" ->
    config = %class_name%Config.new
    expect(config.host).to eq("localhost")

  it "validates required settings" ->
    config = %class_name%Config.new
    expect(-> config.validate!).not_to raise_error
