# Exception — the root of everything `raise` can carry. Treat it as
# abstract: raise a subclass. `Error` (rescuable failures) descends from it,
# as do `SystemExit` and `Interrupt`, which a `rescue e: Error` does not
# catch. Every exception has a message.
+ Exception
  rw :message

  -> new(@message)

  -> to_s
    @message
