# StandardError — Ruby's name for the ordinary rescuable error, kept so code
# written `+ ConfigError < StandardError` (common in ports from Ruby) gets a
# real error class: Error's constructor, message, code and cause, matched by
# `rescue e: Error`. New code should subclass Error (or a specific subclass).
+ StandardError < Error
