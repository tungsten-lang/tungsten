use TungstenSpec

describe %class_name% ->
  it "succeeds with valid params" ->
    result = %class_name%.call()
    expect(result.success?).to eq(true)
