package main

import "fmt"

func main() {
	sum := int64(0)
	i := int64(1)
	for i <= 3500000000 {
		sum += i
		i++
	}
	fmt.Println(sum)
}
