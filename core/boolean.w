# Boolean — true (subtag 0x2) and false (subtag 0x1) singletons.
+ Boolean

+ True < Boolean
  is Inspectable
  is Printable

  -> object_id 2
  -> hash      2

  -> &/1 @1 ? true : false
  -> |/1 true
  -> ^/1 @1 ? false : true

  -> !/0  false

  -> to_s    "true"
  -> inspect "true"

+ False < Boolean
  is Inspectable
  is Printable

  -> object_id 1
  -> hash      1

  -> &/1 false
  -> |/1 @1 ? true : false
  -> ^/1 @1 ? true : false

  -> !/0  true

  -> to_s    "false"
  -> inspect "false"
