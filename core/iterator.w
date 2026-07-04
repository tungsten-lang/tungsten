+ Iterator
  is Enumerable

  abstract
    -> next
    -> reset

  -> each
    self

  -> map
  -> select
  -> reject
  -> detect
  -> take/1
  -> skip/1
  -> zip/1
  -> cycle

  -> uniq
    self & self

  -> with_index(offset = 0)

  -> with_object/1

  # @arg n [#to_i]
  -> slice/1
    raise ArgumentError, "Invalid slice size: [@1]" if @1 <= 0

  # @arg n [#to_i]
  -> cons/1
    raise ArgumentError, "Invalid cons size: [@1]" if @1 <= 0

  # @arg other [Iterator]
  -> chain/1

  -> tap(&)
