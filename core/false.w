+ False < Boolean
  is Inspectable
  is Printable

  -> object_id 1
  -> hash      1

  -> &/1 false
  -> |/1 @1 ? true : false
  -> ^/1 @1 ? true : false

  -> !/0  true
  -> nil? false

  -> to_s    "false"
  -> inspect "false"
