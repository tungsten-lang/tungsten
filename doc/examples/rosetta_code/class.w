+ Animal
  -> .inherited(subclass)
    << "new subclass of [self]: [subclass]"

+ Cat < Animal
+ Dog < Animal

+ Lab    < Dog
+ Collie < Dog

##############

+ Animal
  + Cat
  + Dog
    + Lab
    + Collie

## expect stdout
