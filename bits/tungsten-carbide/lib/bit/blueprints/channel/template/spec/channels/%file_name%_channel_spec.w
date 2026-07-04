use TungstenSpec

describe %class_name%Channel ->
  it "subscribes to the channel" ->
    conn = Channel:Connection.new(MockSocket.new)
    channel = conn.subscribe("%file_name%")
    expect(channel).not_to be_nil
