#include <stdio.h>

int gcd(int a, int b) {
    while (b != 0) {
        int t = b;
        b = a % b;
        a = t;
    }
    return a;
}

int main() {
    int result = 0;
    int i = 1;
    while (i <= 22000000) {
        result += gcd(i, 31415927);
        i += 1;
    }
    printf("%d\n", result);
    return 0;
}
