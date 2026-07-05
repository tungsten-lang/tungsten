#include <stdio.h>

int main() {
    long long sum = 0;
    long long i = 1;
    while (i <= 3500000000LL) {
        sum += i;
        i += 1;
    }
    printf("%lld\n", sum);
    return 0;
}
