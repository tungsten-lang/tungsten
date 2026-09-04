# Typed rescue: `rescue e: Class` binds only errors that are instances of
# Class (or a subclass); anything else propagates to the next handler.
# Several rescue clauses may follow one begin body; the first match wins.
# `rescue Class` with no binding is also accepted. Transcript-diffed between
# the interpreter and the compiled engine by the parity lane.

+ AppError < Error

+ DeepError < AppError

-> classify(kind)
  begin
    if kind == :type
      raise TypeError, "bad type"
    if kind == :app
      raise AppError, "app failed"
    if kind == :deep
      raise DeepError, "deep failed"
    if kind == :plain
      raise "plain string"
    "no error"
  rescue e: DeepError
    "deep: " + e.message
  rescue e: AppError
    "app: " + e.message
  rescue e: TypeError
    "type: " + e.message
  rescue e
    "other: " + e.to_s

<< classify(:none)
<< classify(:type)
<< classify(:app)
<< classify(:deep)
<< classify(:plain)

# An unmatched typed rescue re-raises the ORIGINAL error object to the
# enclosing handler, and ensure still runs on the way out.
-> outer
  log = []
  begin
    begin
      raise KeyError, "missing k"
    rescue e: ArgumentError
      log.push("wrong handler")
    ensure
      log.push("inner ensure")
  rescue e: KeyError
    log.push("outer caught " + e.message)
  log.join(", ")

<< outer

# Class-only clause (no binding), and a subclass matches its parent's clause.
-> class_only
  begin
    raise IndexError, "out of range"
  rescue IndexError
    "index handled"

<< class_only

-> parent_matches
  begin
    raise NoMethodError, "no such method"
  rescue e: NameError
    "name error family: " + e.message

<< parent_matches

# Error fields: code, cause, data travel with the object.
-> with_cause
  begin
    begin
      raise IOError, "disk gone"
    rescue io: IOError
      raise AppError.new("save failed").with_cause(io)
  rescue e: AppError
    e.message + " <- " + e.cause.message + " (" + e.cause.class.to_s + ")"

<< with_cause
