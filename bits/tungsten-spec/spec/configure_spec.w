use spec

configured = false
TungstenSpec.configure ->
  configured = true

describe "TungstenSpec.configure" ->
  it "runs its block immediately" ->
    expect(configured).to be_true

spec_summary
