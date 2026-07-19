# Constructor keyword params — `-> new(@a, name: nil)` was the interpreter
# crasher shape: the kwargs group used to land in the wrong slot as a raw
# hash. Also covers the ivar-assigning keyword form `@scale: 2`.
fn show(v)
  v == nil ? "~" : v.to_s()

+ Widget
  -> new(@a, name: nil)
    @name = name
  -> show_state
    << "widget a=" + show(@a) + " name=" + show(@name)

+ Dec
  -> new(@scale: 2)
  -> show_state
    << "dec scale=" + show(@scale)

Widget.new(5, name: "x").show_state
Widget.new(7).show_state
Widget.new(name: "only").show_state
Dec.new.show_state
Dec.new(scale: 4).show_state
