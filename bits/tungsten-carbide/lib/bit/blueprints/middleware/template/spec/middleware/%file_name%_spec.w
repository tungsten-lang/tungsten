use TungstenSpec

describe %class_name% ->
  it "passes request through" ->
    app = -> (req) Response.ok("ok")
    mw = %class_name%.new
    response = mw.call(Request.new(method: :GET, path: "/"), app)
    expect(response.status).to eq(200)
