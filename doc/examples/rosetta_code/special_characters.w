# Special characters: string escape sequences (shown as codepoints, since
# most are non-printing)

<< "\t".ord
<< "\n".ord
<< "\r".ord
<< "\e".ord
<< "\"".ord
<< "\\".ord

<< "escaped brackets: \[literal, not interpolated\]"
<< "interpolation: [1 + 1]"
<< "raw UTF-8 works directly: héllo wörld"

## expect stdout
## 9
## 10
## 13
## 27
## 34
## 92
## escaped brackets: [literal, not interpolated]
## interpolation: 2
## raw UTF-8 works directly: héllo wörld
