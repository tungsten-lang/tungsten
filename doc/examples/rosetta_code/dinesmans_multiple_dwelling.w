# Dinesman's multiple-dwelling problem

-> abs_val(x)
  if x < 0
    -x
  else
    x

-> solve_dwelling()
  floors = [1, 2, 3, 4, 5]
  floors.each -> (baker)
    floors.each -> (cooper)
      if cooper != baker
        floors.each -> (fletcher)
          if fletcher != baker && fletcher != cooper
            floors.each -> (miller)
              if miller != baker && miller != cooper && miller != fletcher
                floors.each -> (smith)
                  if smith != baker && smith != cooper && smith != fletcher && smith != miller
                    if baker != 5 && cooper != 1 && fletcher != 1 && fletcher != 5 && miller > cooper && abs_val(smith - fletcher) != 1 && abs_val(fletcher - cooper) != 1
                      << "Baker=[baker], Cooper=[cooper], Fletcher=[fletcher], Miller=[miller], Smith=[smith]"

solve_dwelling()

## expect stdout
## Baker=3, Cooper=2, Fletcher=4, Miller=5, Smith=1
