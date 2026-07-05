#include <stdio.h>

int main() {
    int count = 0;
    int i = 0;
    while (i < 1000) {
        int j = 0;
        while (j < 1000) {
            int k = 0;
            while (k < 1000) {
                count = (count + i * 31 + j * 17 + k) % 1000000007;
                k += 1;
            }
            j += 1;
        }
        i += 1;
    }
    printf("%d\n", count);
    return 0;
}
