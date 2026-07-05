package main

import "fmt"

func main() {
	count := 0
	i := 0
	for i < 1000 {
		j := 0
		for j < 1000 {
			k := 0
			for k < 1000 {
				count = (count + i*31 + j*17 + k) % 1000000007
				k++
			}
			j++
		}
		i++
	}
	fmt.Println(count)
}
