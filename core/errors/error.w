# Error — the base class of every rescuable error.
#
# `raise Cls, "msg"` builds `Cls.new("msg")`; `rescue e: Cls` binds only an
# instance of Cls or one of its subclasses. Runtime failures (division by
# zero, undefined methods, frozen mutation, ...) are raised as the matching
# subclass whenever the class is linked into the program, so the same clause
# catches errors from Tungsten code and from the runtime alike.
#
# Fields: `message` (always), `code` (a stable symbol such as
# :E_LOWER_ARITY), `cause` (the error this one wraps), `data` (any extra
# structured detail), `backtrace` (frames, when the runtime attaches them).
+ Error < Exception
  rw :message
  rw :code
  rw :cause
  rw :data
  rw :backtrace

  -> new(@message)

  -> with_cause(err)
    @cause = err
    self

  -> with_code(c)
    @code = c
    self

  -> with_data(d)
    @data = d
    self

  # "Class: message", followed by one indented line per wrapped cause.
  -> full_message
    text = self.class_name + ": " + @message.to_s
    if @cause != nil
      if @cause.is_a?(Error)
        text = text + "\n  caused by " + @cause.full_message
      else
        text = text + "\n  caused by " + @cause.to_s
    text

  -> to_s
    @message
