+ Parent<T>
  with T in (i32 f32)

+ Child<T> < Parent<T>

+ NarrowChild<T> < Parent<T>
  with T in (i32)

Child<f32>.new()
NarrowChild<i32>.new()
