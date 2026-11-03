use spec
use ../lib/wassat

-> sorting_input_fixture(missing, contradiction)
  cs = [[-7,1,2],[7,-1],[-8,2,4],[8,-2],[8,-4],[-11,1],[11,-1],[12,4],[-12,-4],
    [9,7],[-10,8],[9,10,11],[13,7],[-14,8],[13,14,12]]
  cs.push([7,-2]) unless missing
  cs.push([9,-12]) if contradiction
  total = 0
  cs.each -> (c) total += c.size
  lits = i64[total]; offs = i64[cs.size]; lens = i64[cs.size]; at = 0; i = 0
  cs.each -> (c)
    offs[i] = at; lens[i] = c.size
    c.each -> (v)
      lits[at] = v; at += 1
    i += 1
  { "nvars": 14, "flat_ncl": cs.size, "flat_nlits": total,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

-> sorting_input_decode(f, m, stop, deadline)
  group = i32[7]; a = i32[7]; b = i32[7]; id = 1; x = 0
  while x < 4
    y = x+1
    while y < 4
      a[id] = x; b[id] = y; id += 1; y += 1
    x += 1
  m[0] = 4
  wassat_sorting_encoded_inputs(f,6,6,group,a,b,m,stop,deadline)

describe "Shared comparator controls" ->
  it "separates input circuits sharing an OR and recovers both bit polarities" ->
    m = i64[32]
    v = sorting_input_decode(sorting_input_fixture(false,false),m,i64[4],clock_ms()+5000)
    expect(v != nil).to eq(true)
    expect(m[29]).to eq(4); expect(m[4]).to eq(2); expect(m[31]).to eq(2)
    expect(v[0]).to eq(9); expect(v[1]).to eq(11)
    expect(m[30] > 0).to eq(true)
  it "requires every reverse implication before splitting a shared control" ->
    m = i64[32]
    v = sorting_input_decode(sorting_input_fixture(true,false),m,i64[4],clock_ms()+5000)
    expect(v).to eq(nil); expect(m[29]).to eq(3)
  it "rejects conflicting input observations" ->
    expect(sorting_input_decode(sorting_input_fixture(false,true),i64[32],i64[4],clock_ms()+5000)).to eq(nil)
  it "polls cancellation before decoding" ->
    stop = i64[4]; z = wassat_stop_cancel(stop); m = i64[32]
    expect(sorting_input_decode(sorting_input_fixture(false,false),m,stop,clock_ms()+5000)).to eq(nil)
    expect(m[10]).to eq(1); expect(m[29]).to eq(0)
  it "honors an expired decoding deadline" ->
    m = i64[32]
    expect(sorting_input_decode(sorting_input_fixture(false,false),m,i64[4],0)).to eq(nil)
    expect(m[10]).to eq(2)

spec_summary
