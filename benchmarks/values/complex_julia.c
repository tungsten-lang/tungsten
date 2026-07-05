#include <stdio.h>
#include <time.h>

int main(void) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    double c_re = -0.7;
    double c_im = 0.27015;
    long long total = 0;
    for (int py = 0; py < 2000; py++) {
        double zi_init = -1.5 + py * 3.0 / 2000.0;
        for (int px = 0; px < 2000; px++) {
            double zr = -1.5 + px * 3.0 / 2000.0;
            double zi = zi_init;
            int iter = 0;
            while (iter < 50) {
                if (zr * zr + zi * zi > 4.0) break;
                double new_zr = zr * zr - zi * zi + c_re;
                zi = 2.0 * zr * zi + c_im;
                zr = new_zr;
                iter++;
            }
            total += iter;
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    printf("%lld\n", total);
    printf("elapsed: %.3fs\n", elapsed);
    return 0;
}
