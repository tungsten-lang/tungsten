package main

import "fmt"

func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}

func main() {
	result := 0
	i := 1
	for i <= 22000000 {
		result += gcd(i, 31415927)
		i++
	}
	fmt.Println(result)
}
