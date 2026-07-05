package main

import (
	"fmt"
	"strings"
)

func levenshtein(s, t string) int {
	m, n := len(s), len(t)
	if m == 0 {
		return n
	}
	if n == 0 {
		return m
	}

	prev := make([]int, n+1)
	curr := make([]int, n+1)
	for j := 0; j <= n; j++ {
		prev[j] = j
	}

	for i := 0; i < m; i++ {
		curr[0] = i + 1
		for j := 0; j < n; j++ {
			cost := 1
			if s[i] == t[j] {
				cost = 0
			}
			ins := curr[j] + 1
			del := prev[j+1] + 1
			sub := prev[j] + cost
			best := ins
			if del < best {
				best = del
			}
			if sub < best {
				best = sub
			}
			curr[j+1] = best
		}
		prev, curr = curr, prev
	}

	return prev[n]
}

func main() {
	s := strings.Repeat("the quick brown fox jumps over the lazy dog", 20)
	t := strings.Repeat("the slow brown fox leaps over the lazy cat", 20)
	fmt.Println(levenshtein(s, t))
}
