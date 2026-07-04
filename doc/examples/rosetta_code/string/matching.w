<< "abcd".starts_with?("ab")
<< "abcd".ends_with?("ab")
<< "abcd".include?("aa")
<< "abab".index("aa") == nil
<< "abab".index("ab")

## expect stdout
## true
## false
## false
## true
## 0
