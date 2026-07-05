#include <stdio.h>

int collatz_steps(long long n) {
    int steps = 0;
    while (n != 1) {
        if (n % 2 == 0)
            n = n / 2;
        else
            n = 3 * n + 1;
        steps += 1;
    }
    return steps;
}

int main() {
    int total = 0;
    int i = 1;
    while (i <= 5000000) {
        total += collatz_steps(i);
        i += 1;
    }
    printf("%d\n", total);
    return 0;
}
