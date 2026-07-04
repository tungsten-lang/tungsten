# Carbide::Notifier — multi-channel notifications
# Send notifications via email, push, webhook, or any custom channel.
# Each delivery method is a separate class with a `deliver` method.

in Tungsten:Carbide

+ Notifier
  ro :recipient
  ro :params

  @@delivery_methods = []

  # --- Class-level DSL ---

  -> .deliver_via(*methods)
    @@delivery_methods = methods

  -> .delivery_methods
    @@delivery_methods

  # --- Instance ---

  -> new(@recipient, **params)
    @params = params

  # Override in subclasses — build the notification content per channel
  -> message_for(channel)
    <! "Notifier#message_for(#{channel}) must be implemented"

  # --- Delivery ---

  -> deliver
    self.class.delivery_methods.each -> (method)
      self.deliver_to(method)

  -> deliver_later
    self.class.delivery_methods.each -> (method)
      NotificationJob.perform_async(self.class.name, @recipient.id, method, @params)

  -> deliver_to(method)
    message = self.message_for(method)
    channel = DeliveryChannel.for(method)
    channel.deliver(message, to: @recipient)

  # --- Delivery channels ---

  + DeliveryChannel
    @@registry = {}

    -> .register(name, channel_class)
      @@registry[name] = channel_class

    -> .for(name)
      @@registry[name] || <! "Unknown delivery channel: #{name}"

    -> deliver(message, to:)
      <! "DeliveryChannel#deliver must be implemented"

  + EmailChannel < DeliveryChannel
    -> deliver(message, to:)
      Mailer.deliver(
        to: to.email,
        subject: message[:subject],
        body: message[:body]
      )

  + PushChannel < DeliveryChannel
    -> deliver(message, to:)
      PushService.send(
        device_token: to.push_token,
        title: message[:title],
        body: message[:body]
      )

  + WebhookChannel < DeliveryChannel
    -> deliver(message, to:)
      HTTP.post(
        to.webhook_url,
        headers: {"Content-Type" => "application/json"},
        body: JSON.encode(message)
      )

  # Register built-in channels
  DeliveryChannel.register(:email, EmailChannel)
  DeliveryChannel.register(:push, PushChannel)
  DeliveryChannel.register(:webhook, WebhookChannel)

  # --- Notification job for async delivery ---

  + NotificationJob[Job]
    queue_as :notifications

    -> perform(notifier_name, recipient_id, method, params)
      notifier_class = Object.const_get(notifier_name)
      recipient = Account.find(recipient_id)
      notifier = notifier_class.new(recipient, **params)
      notifier.deliver_to(method)
