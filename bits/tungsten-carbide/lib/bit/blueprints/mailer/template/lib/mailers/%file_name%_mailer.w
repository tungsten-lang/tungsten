# %class_name%Mailer — email sender for %name%-related emails
use Tungsten:Carbide

+ %class_name%Mailer < Carbide:Mailer
  default from: "noreply@example.com"

  # Send a notification email
  #
  # Usage:
  #   %class_name%Mailer.notification(user).deliver_now
  #   %class_name%Mailer.notification(user).deliver_later
  -> notification(recipient)
    @recipient = recipient

    mail(
      to:      recipient.email,
      subject: "%class_name% Notification"
    )
