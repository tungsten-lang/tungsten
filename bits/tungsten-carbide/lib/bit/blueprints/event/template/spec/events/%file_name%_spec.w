use TungstenSpec

describe %class_name% ->
  it "records the event" ->
    event = %class_name%.new(nil)
    expect(event.occurred_at).not_to be_nil
    expect(event.id).not_to be_nil
