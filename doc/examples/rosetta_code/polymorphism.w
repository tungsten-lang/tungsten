# Polymorphism: a shared method (describe) dispatches to whichever
# override of area each runtime type provides — the caller never checks
# what kind of Shape it has.

+ Shape
  -> area
    0

  -> describe
    << "[self.class_name]: area = [area]"

+ Circle < Shape
  -> new(@radius) ro
  -> area
    3.14159265 * radius * radius

+ Rectangle < Shape
  -> new(@width, @height) ro
  -> area
    width * height

+ Square < Shape
  -> new(@side) ro
  -> area
    side * side

shapes = [Circle(3), Rectangle(4, 5), Square(6)]
shapes.each -> (s)
  s.describe

## expect stdout
## Circle: area = 28.27433385
## Rectangle: area = 20
## Square: area = 36
