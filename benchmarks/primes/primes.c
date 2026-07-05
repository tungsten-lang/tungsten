#include <stdio.h>

int is_prime(int n) {
    if (n < 2) return 0;
    if (n < 4) return 1;
    if (n % 2 == 0 || n % 3 == 0) return 0;
    int i = 5;
    while (i * i <= n) {
        if (n % i == 0 || n % (i + 2) == 0) return 0;
        i += 6;
    }
    return 1;
}

int main() {
    int count = 0;
    for (int n = 2; n <= 120000000; n++) {
        if (is_prime(n)) count++;
    }
    printf("%d\n", count);
    return 0;
}
