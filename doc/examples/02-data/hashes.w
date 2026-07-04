# Hash operations
person = {name: "Alice", age: 30, city: "Portland"}

<< "Name:   [person[:name]]"
<< "Keys:   name, age, city"
<< "Values: [person[:name]], [person[:age]], [person[:city]]"
<< "Size:   [person.size]"
<< "Has name? [person[:name] != nil]"

## expect stdout
## Name:   Alice
## Keys:   name, age, city
## Values: Alice, 30, Portland
## Size:   3
## Has name? true
