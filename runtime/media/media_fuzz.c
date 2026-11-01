/* Standalone deterministic malformed-TWMS corpus runner. Build with the script
 * below so the segment parser itself is instrumented by ASan and UBSan. */
#include "runtime.h"
#include "wvalue.h"
#include "media.h"
#include <stdio.h>
int main(int argc, char **argv) {
    char error[1024];
    for (int i = 1; i < argc; i++) {
        WMediaSegment *segment = w_media_seg_load(argv[i], error, sizeof error);
        if (segment) w_media_seg_free(segment);
    }
    return 0;
}
