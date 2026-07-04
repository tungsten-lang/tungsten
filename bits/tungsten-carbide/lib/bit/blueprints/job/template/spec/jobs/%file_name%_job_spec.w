use TungstenSpec

describe %class_name%Job ->
  it "performs the job" ->
    job = %class_name%Job.new
    expect(-> job.execute).not_to raise_error
