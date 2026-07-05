package main

import "core:fmt"
import "core:strings"

levenshtein :: proc(s, t: string) -> int {
    m := len(s)
    n := len(t)
    if m == 0 do return n
    if n == 0 do return m

    prev := make([]int, n + 1)
    curr := make([]int, n + 1)
    defer delete(prev)
    defer delete(curr)

    for j in 0..=n do prev[j] = j

    for i in 0..<m {
        curr[0] = i + 1
        for j in 0..<n {
            cost := 1
            if s[i] == t[j] do cost = 0
            ins := curr[j] + 1
            del := prev[j + 1] + 1
            sub := prev[j] + cost
            best := ins
            if del < best do best = del
            if sub < best do best = sub
            curr[j + 1] = best
        }
        prev, curr = curr, prev
    }

    return prev[n]
}

main :: proc() {
    s := strings.repeat("the quick brown fox jumps over the lazy dog", 20)
    t := strings.repeat("the slow brown fox leaps over the lazy cat", 20)
    defer delete(s)
    defer delete(t)
    fmt.println(levenshtein(s, t))
}
