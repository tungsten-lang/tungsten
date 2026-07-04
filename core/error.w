# Error — base error class
+ Error
  rw :message

  -> new(@message)

  -> to_s
    @message
