# Integer sequence: print successive positive integers (capped here so the
# example terminates; drop the .to_a and loop `i += 1` forever for the
# unbounded version)

(1..10).each -> (i)
  << i

## expect stdout
## 1
## 2
## 3
## 4
## 5
## 6
## 7
## 8
## 9
## 10
