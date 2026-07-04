use Tungsten:Spec

describe %class_name%Mailer ->
  let :recipient, build(:user, email: "test@example.com", name: "Test User")

  describe "#notification" ->
    let :mail, %class_name%Mailer.notification(recipient)

    it "sends to the recipient" ->
      expect(mail.to).to eq("test@example.com")

    it "sets the subject" ->
      expect(mail.subject).to eq("%class_name% Notification")

    it "sets the from address" ->
      expect(mail.from).to eq("noreply@example.com")

    it "renders the body" ->
      expect(mail.html_body).to include("Hello, Test User")
