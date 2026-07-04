+ True < Boolean
  is Inspectable
  is Printable

  -> object_id 2
  -> hash      2

  -> &/1 @1 ? true : false
  -> |/1 true
  -> ^/1 @1 ? false : true

  -> !/0  false
  -> nil? false

  -> to_s    "true"
  -> inspect "true"
