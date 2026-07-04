in Notifiers

+ %class_name%Notifier[Notifier]
  deliver_via :email

  -> message_for(channel)
    case channel
      :email =>
        {
          subject: "Notification",
          body: "Hello #{self.recipient.username}"
        }
