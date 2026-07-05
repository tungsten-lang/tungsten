package main

import "fmt"

func collatzSteps(n int64) int {
	steps := 0
	for n != 1 {
		if n%2 == 0 {
			n = n / 2
		} else {
			n = 3*n + 1
		}
		steps++
	}
	return steps
}

func main() {
	total := 0
	i := int64(1)
	for i <= 5000000 {
		total += collatzSteps(i)
		i++
	}
	fmt.Println(total)
}
