/* Check the native array boundary contract across storage widths and tiers.
 * Successful WArray checks must retain all mismatch and borrowed-view guards. */
#include "../runtime.h"
#include <assert.h>
#include <stdio.h>
#include <setjmp.h>
static int checks;
static void check_guard(WValue arr, int bits, int poly, int passes, int big) {
    WExceptionFrame frame;
    w_exception_frame_push(&frame);
    if (W_FAST_SETJMP(frame.buf) == 0) {
        WValue out = w_check_array_ebits(arr, bits, poly, w_string("guard contract"));
        assert(passes);
        if (big) {
            WBigArray *b = (WBigArray *)w_as_ptr(arr);
            WArray *a = w_as_array(out);
            assert(w_is_array(out) && a->slots == (WValue *)b->slots);
            assert(a->start == b->start && a->size == b->size);
            assert(a->ebits == (int8_t)b->ebits);
        } else assert(out == arr);
    } else {
        assert(!passes);
        assert(w_exception_error() != W_NIL);
    }
    w_exception_pop();
    ++checks;
}
int main(void) {
    const int kinds[][2] = {{1,1},{4,4},{-4,4},{8,8},{108,8},{16,16},
        {116,16},{32,32},{33,32},{64,64},{65,64},{66,64},{-16,16},
        {-32,32},{-64,64},{-116,16},{-108,8},{-109,8},{-104,4}};
    const int widths[] = {1,4,8,16,32,64};
    for (size_t k = 0; k < sizeof(kinds)/sizeof(kinds[0]); ++k) {
        for (int tier = 0; tier < 3; ++tier) {
            if (tier == 1 && kinds[k][0] < 0) continue;
            WValue arr = tier == 0 ? w_array_new(kinds[k][0], 7) :
                         tier == 1 ? w_small_array_new(kinds[k][0], 7, 0) :
                                     w_big_array_new(kinds[k][0], 7);
            for (size_t wi = 0; wi < sizeof(widths)/sizeof(widths[0]); ++wi)
                for (int poly = 0; poly < 2; ++poly)
                    check_guard(arr, widths[wi], poly,
                        widths[wi] == kinds[k][1] && poly == (kinds[k][0] == 65), tier == 2);
        }
    }
    /* Guard-only oracle: vary metadata without indexing the backing storage.
     * Unrecognized legacy codes must still follow array_storage_bits. */
    WValue forged = w_array_new(64, 1);
    const int all_widths[] = {-1,0,1,4,8,16,32,64,127,128,129};
    for (int code = -128; code <= 127; ++code) {
        w_as_array(forged)->ebits = (int8_t)code;
        for (size_t wi = 0; wi < sizeof(all_widths)/sizeof(all_widths[0]); ++wi)
            for (int poly = 0; poly < 2; ++poly)
                check_guard(forged, all_widths[wi], poly,
                    all_widths[wi] == w_array_storage_bits(code) && poly == (code == 65), 0);
    }
    w_as_array(forged)->ebits = 64;
    WValue scalar[] = {W_NIL,W_TRUE,w_int(123),w_string("not an array")};
    for (size_t i = 0; i < sizeof(scalar)/sizeof(scalar[0]); ++i)
        check_guard(scalar[i],64,0,1,0);
    unsigned char bytes[8] = {1,2,3,4,5,6,7,8};
    WValue b = w_big_array_view(bytes,8,8);
    WValue v = w_check_array_ebits(b,8,0,w_string("view"));
    assert(v == w_check_array_ebits(b,8,0,w_string("view")));
    w_array_set(v,w_int(2),w_int(99)); assert(bytes[2] == 99);
    WBigArray *big = (WBigArray *)w_as_ptr(b); big->start = 2; big->size = 3;
    check_guard(b,8,0,1,1);
    assert(w_as_int(w_array_get(v,w_int(0))) == 99);
    big->size = INT32_MAX;
    check_guard(b,8,0,0,1);
    printf("typed-array parameter guard: %d checks passed\n",checks);
    return 0;
}
