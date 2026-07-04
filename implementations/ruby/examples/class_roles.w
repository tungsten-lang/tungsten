in MyApp
  Controller = Base:Controller
  Model = Base:Model

+ Users[Controller]
  -> index
    << "user list"

+ User[Model]
  ro :name
  ro :email
