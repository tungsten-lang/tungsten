use TungstenSpec

describe %class_name%Policy ->
  let :account -> Account.new(id: 1)
  let :record  -> %class_name%.new(account_id: 1)
  let :policy  -> %class_name%Policy.new(account, record)

  it "allows index" ->
    expect(policy.index?).to eq(true)

  it "allows show" ->
    expect(policy.show?).to eq(true)

  it "allows owner to update" ->
    expect(policy.update?).to eq(true)

  it "denies non-owner update" ->
    other = Account.new(id: 2)
    p = %class_name%Policy.new(other, record)
    expect(p.update?).to eq(false)
