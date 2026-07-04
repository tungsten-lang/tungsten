# Carbide::Mailer — email composition and delivery
# Define mailer classes with methods that build email messages.

in Tungsten:Carbide

+ Mailer
  ro :message

  @@default_from    = nil
  @@delivery_method = :smtp
  @@delivery_config = {}

  # --- Class-level configuration ---

  -> .default(from: nil, reply_to: nil)
    @@default_from     = from if from
    @@default_reply_to = reply_to if reply_to

  -> .delivery_method(method, **config)
    @@delivery_method = method
    @@delivery_config = config

  # --- Build and send ---

  # Class method to invoke a mailer action and return the message
  -> .method_missing(name, *args)
    instance = self.new
    instance.send(name, *args)
    instance.message

  -> new
    @message = Email.new
    @message.from = @@default_from

  -> mail(to:, subject:, body: nil, html: nil, from: nil, cc: nil, bcc: nil, reply_to: nil)
    @message.to       = to
    @message.subject  = subject
    @message.from     = from || @@default_from
    @message.cc       = cc
    @message.bcc      = bcc
    @message.reply_to = reply_to || @@default_reply_to

    if html
      @message.html_body = html
    elsif body
      @message.text_body = body
    else
      # Render template based on mailer/action name
      @message.html_body = render_mail_template

    @message

  -> render_mail_template
    mailer_name = self.class.name.underscore
    action = caller_method_name
    View.new("#{mailer_name}/#{action}", layout: "mailer", locals: instance_variables_hash).render

  # Deliver now
  -> deliver_now
    Delivery.send(@message, method: @@delivery_method, config: @@delivery_config)

  # Deliver via background worker
  -> deliver_later
    MailerWorker.perform_async(self.class.name, @message.serialize)


# Email message object
+ Email
  rw :from
  rw :to
  rw :cc
  rw :bcc
  rw :reply_to
  rw :subject
  rw :text_body
  rw :html_body
  rw :attachments

  -> new
    @attachments = []

  -> attach(filename, content, content_type: "application/octet-stream")
    @attachments.push({filename: filename, content: content, content_type: content_type})

  -> serialize
    {
      from: @from, to: @to, cc: @cc, bcc: @bcc,
      reply_to: @reply_to, subject: @subject,
      text_body: @text_body, html_body: @html_body
    }

  -> .deserialize(data)
    email = self.new
    data.each -> (key, value)
      email.send("#{key}=", value)
    email
