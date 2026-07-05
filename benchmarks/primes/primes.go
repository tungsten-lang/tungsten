package main

import "fmt"

func isPrime(n int) bool {
	if n < 2 {
		return false
	}
	if n < 4 {
		return true
	}
	if n%2 == 0 || n%3 == 0 {
		return false
	}
	for i := 5; i*i <= n; i += 6 {
		if n%i == 0 || n%(i+2) == 0 {
			return false
		}
	}
	return true
}

func main() {
	count := 0
	for n := 2; n <= 120000000; n++ {
		if isPrime(n) {
			count++
		}
	}
	fmt.Println(count)
}
