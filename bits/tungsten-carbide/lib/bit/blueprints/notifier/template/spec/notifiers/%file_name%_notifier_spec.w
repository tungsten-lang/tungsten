use TungstenSpec

describe %class_name%Notifier ->
  let :recipient -> Account.new(username: "test", email: "test@example.com")

  it "builds email message" ->
    notifier = %class_name%Notifier.new(recipient)
    message = notifier.message_for(:email)
    expect(message[:subject]).not_to be_nil
