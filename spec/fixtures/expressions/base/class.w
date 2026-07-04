in Tmp
  + A
  + B < A

ex "Tmp:A.class", Tmp:A
ex "Tmp:B.class", Tmp:B

ex "Tmp:B.superclass", Tmp:A
ex "Tmp:A.superclass", Obj
ex "Obj.superclass",   nil
