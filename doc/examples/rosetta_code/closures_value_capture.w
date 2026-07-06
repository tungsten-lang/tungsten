# Closures / Value capture — each closure created in the loop captures the
# loop variable's value at that iteration, not a shared reference to it (so
# calling them afterward doesn't just return the final i three times over).

closures = []
(0..2).each -> (i)
  closures.push(-> () i * i)

closures.each -> (c)
  << c()

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten closures_value_capture.w`
## expect stdout
## 0
## 1
## 4
