/*
 * Benchmark-only references for Date operations migrated from runtime.c to
 * core/date.w. These intentionally mirror the removed C IC handler bodies so
 * the executable can compare native Tungsten and C through the same Date
 * method-dispatch path.
 */

#include "runtime.h"

static int ref_date_leap_year(int y) {
    return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
}

static int ref_date_days_in_month(int y, int m) {
    static const int days[] = {0, 31, 28, 31, 30, 31, 30,
                              31, 31, 30, 31, 30, 31};
    if (m == 2 && ref_date_leap_year(y)) return 29;
    return days[m];
}

static int64_t ref_date_jdn(WValue d) {
    int y = w_unbox_date_year(d);
    int m = w_unbox_date_month(d);
    int day = w_unbox_date_day(d);
    int a = (14 - m) / 12;
    int yy = y + 4800 - a;
    int mm = m + 12 * a - 3;
    return day + (153 * mm + 2) / 5 + 365 * yy + yy / 4 -
           yy / 100 + yy / 400 - 32045;
}

static int ref_date_iso_weekday(int64_t jdn) {
    return (int)(((jdn % 7) + 7) % 7) + 1;
}

static int ref_date_yday(WValue d) {
    int y = w_unbox_date_year(d);
    int m = w_unbox_date_month(d);
    int yd = w_unbox_date_day(d);
    for (int i = 1; i < m; i++) yd += ref_date_days_in_month(y, i);
    return yd;
}

static int ref_date_weeks_in_year(int y) {
    int wd = ref_date_iso_weekday(
        ref_date_jdn(w_box_date(y, 1, 1, 0, 0, 0, 0)));
    return (wd == 4 || (ref_date_leap_year(y) && wd == 3)) ? 53 : 52;
}

static int ref_date_iso_week(WValue d) {
    int y = w_unbox_date_year(d);
    int wd = ref_date_iso_weekday(ref_date_jdn(d));
    int week = (ref_date_yday(d) - wd + 10) / 7;
    if (week < 1) return ref_date_weeks_in_year(y - 1);
    if (week > ref_date_weeks_in_year(y)) return 1;
    return week;
}

WValue w_ref_date_year(WValue d) { return w_int(w_unbox_date_year(d)); }
WValue w_ref_date_month(WValue d) { return w_int(w_unbox_date_month(d)); }
WValue w_ref_date_day(WValue d) { return w_int(w_unbox_date_day(d)); }
WValue w_ref_date_hour(WValue d) { return w_int(w_unbox_date_hour(d)); }
WValue w_ref_date_minute(WValue d) { return w_int(w_unbox_date_min(d)); }
WValue w_ref_date_second(WValue d) { return w_int(w_unbox_date_sec(d)); }
WValue w_ref_date_tz(WValue d) { return w_int(w_unbox_date_tz(d)); }

WValue w_ref_date_wday(WValue d) {
    return w_int((int)(((ref_date_jdn(d) + 1) % 7 + 7) % 7));
}

WValue w_ref_date_yday(WValue d) { return w_int(ref_date_yday(d)); }
WValue w_ref_date_cweek(WValue d) { return w_int(ref_date_iso_week(d)); }
WValue w_ref_date_cwday(WValue d) {
    return w_int(ref_date_iso_weekday(ref_date_jdn(d)));
}
WValue w_ref_date_days_in_month(WValue d) {
    return w_int(ref_date_days_in_month(w_unbox_date_year(d),
                                       w_unbox_date_month(d)));
}
WValue w_ref_date_days_in_year(WValue d) {
    return w_int(ref_date_leap_year(w_unbox_date_year(d)) ? 366 : 365);
}
WValue w_ref_date_leap_p(WValue d) {
    return ref_date_leap_year(w_unbox_date_year(d)) ? W_TRUE : W_FALSE;
}
WValue w_ref_date_jd(WValue d) { return w_int(ref_date_jdn(d)); }
WValue w_ref_date_quarter(WValue d) {
    return w_int((w_unbox_date_month(d) - 1) / 3 + 1);
}
