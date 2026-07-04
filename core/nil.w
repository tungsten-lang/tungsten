+ Nil
  is Inspectable
  is Printable

  -> object_id 0
  -> hash 0

  -> ==/1:nil
    true

  -> &/1 false
  -> |/1 @1 ? true : false
  -> ^/1 @1 ? true : false

  -> !/0    true
  -> blank? true
  -> nil?   true

  -> try(&) self

  -> to_a []
  -> to_c
  -> to_d 0.0
  -> to_f 0.0f
  -> to_h {}
  -> to_i 0
  -> to_r Rational.new(0, 1)
  -> to_s ""

  -> inspect "nil"
