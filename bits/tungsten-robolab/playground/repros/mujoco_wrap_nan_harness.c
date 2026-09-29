// The functions is_intersect, length_circle and wrap_circle below are copied from MuJoCo 3.6.0, src/engine/engine_util_misc.c
// (Copyright 2021 DeepMind Technologies Limited, Apache License 2.0, https://github.com/google-deepmind/mujoco); the mju_* helpers are
// minimal re-implementations, and the CLAMP switch is the proposed fix.
// Standalone harness of MuJoCo 3.6.0's wrap_circle / length_circle (src/engine/engine_util_misc.c, copied verbatim apart from the helper
// definitions) fed with the 2D inputs of the failing substep (91049 at t = 16.517 s) and a sweep of last-bit perturbations of them.
// Purpose: show at SOURCE level that the NaN is acos(dot > 1.0) in length_circle, and that clamping the dot removes every NaN.
//   clang -O2 -o /tmp/wrap_harness playground/repros/mujoco_wrap_nan_harness.c -lm && /tmp/wrap_harness
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef double mjtNum;
typedef unsigned char mjtByte;
#define mjMINVAL 1e-15
#define mjPI 3.14159265358979323846
#define mju_sqrt sqrt
#define mju_acos acos
#define mju_abs fabs

static mjtNum mju_dot(const mjtNum* a, const mjtNum* b, int n) {
  mjtNum res = 0;
  for (int i = 0; i < n; i++) res += a[i] * b[i];
  return res;
}
static mjtNum mju_normalize(mjtNum* vec, int n) {
  mjtNum norm = mju_sqrt(mju_dot(vec, vec, n));
  if (norm < mjMINVAL) {
    vec[0] = 1;
    for (int i = 1; i < n; i++) vec[i] = 0;
  } else {
    mjtNum normInv = 1 / norm;
    for (int i = 0; i < n; i++) vec[i] *= normInv;
  }
  return norm;
}
static void mju_add(mjtNum* res, const mjtNum* a, const mjtNum* b, int n) { for (int i = 0; i < n; i++) res[i] = a[i] + b[i]; }
static void mju_sub(mjtNum* res, const mjtNum* a, const mjtNum* b, int n) { for (int i = 0; i < n; i++) res[i] = a[i] - b[i]; }

static int CLAMP = 0;

static mjtByte is_intersect(const mjtNum* p1, const mjtNum* p2, const mjtNum* p3, const mjtNum* p4) {
  mjtNum a, b;
  mjtNum det = (p4[1]-p3[1])*(p2[0]-p1[0]) - (p4[0]-p3[0])*(p2[1]-p1[1]);
  if (mju_abs(det) < mjMINVAL) return 0;
  a = ((p4[0]-p3[0])*(p1[1]-p3[1]) - (p4[1]-p3[1])*(p1[0]-p3[0])) / det;
  b = ((p2[0]-p1[0])*(p1[1]-p3[1]) - (p2[1]-p1[1])*(p1[0]-p3[0])) / det;
  return ((a >= 0 && a <= 1 && b >= 0 && b <= 1) ? 1 : 0);
}

static mjtNum g_last_dot;
static mjtNum length_circle(const mjtNum* p0, const mjtNum* p1, int ind, mjtNum radius) {
  mjtNum p0n[2] = {p0[0], p0[1]};
  mjtNum p1n[2] = {p1[0], p1[1]};
  mju_normalize(p0n, 2);
  mju_normalize(p1n, 2);
  mjtNum dot = mju_dot(p0n, p1n, 2);
  g_last_dot = dot;
  if (CLAMP) dot = dot > 1 ? 1 : (dot < -1 ? -1 : dot);        // <-- the proposed fix
  mjtNum angle = mju_acos(dot);
  mjtNum cross = p0[1]*p1[0]-p0[0]*p1[1];
  if ((cross > 0 && ind) || (cross < 0 && !ind)) angle = 2*mjPI - angle;
  return radius*angle;
}

static mjtNum wrap_circle(mjtNum pnt[4], const mjtNum end[4], const mjtNum* side, mjtNum radius) {
  mjtNum sqlen0 = end[0]*end[0] + end[1]*end[1];
  mjtNum sqlen1 = end[2]*end[2] + end[3]*end[3];
  mjtNum sqrad = radius*radius;
  if (sqlen0 < sqrad || sqlen1 < sqrad || radius < mjMINVAL) return -1;
  mjtNum dif[2] = {end[2]-end[0], end[3]-end[1]};
  mjtNum dd = dif[0]*dif[0] + dif[1]*dif[1];
  if (dd < mjMINVAL) return -1;
  mjtNum a = -(dif[0]*end[0]+dif[1]*end[1])/dd;
  if (a < 0) a = 0; else if (a > 1) a = 1;
  mjtNum tmp[2] = {a*dif[0] + end[0], a*dif[1] + end[1]};
  if (tmp[0]*tmp[0]+tmp[1]*tmp[1] > sqrad && (!side || mju_dot(side, tmp, 2) >= 0)) return -1;
  mjtNum sqrt0 = mju_sqrt(sqlen0 - sqrad);
  mjtNum sqrt1 = mju_sqrt(sqlen1 - sqrad);
  mjtNum sol[2][2][2], good[2];
  for (int i=0; i < 2; i++) {
    int sgn = (i == 0 ? 1 : -1);
    sol[i][0][0] = (end[0]*sqrad + sgn*radius*end[1]*sqrt0)/sqlen0;
    sol[i][0][1] = (end[1]*sqrad - sgn*radius*end[0]*sqrt0)/sqlen0;
    sol[i][1][0] = (end[2]*sqrad - sgn*radius*end[3]*sqrt1)/sqlen1;
    sol[i][1][1] = (end[3]*sqrad + sgn*radius*end[2]*sqrt1)/sqlen1;
    if (side) {
      mju_add(tmp, sol[i][0], sol[i][1], 2);
      mju_normalize(tmp, 2);
      good[i] = mju_dot(tmp, side, 2);
    } else {
      mju_sub(tmp, sol[i][0], sol[i][1], 2);
      good[i] = -mju_dot(tmp, tmp, 2);
    }
    if (is_intersect(end, sol[i][0], end+2, sol[i][1])) good[i] = -10000;
  }
  int i = (good[0] > good[1] ? 0 : 1);
  pnt[0] = sol[i][0][0]; pnt[1] = sol[i][0][1]; pnt[2] = sol[i][1][0]; pnt[3] = sol[i][1][1];
  if (is_intersect(end, pnt, end+2, pnt+2)) return -1;
  return length_circle(sol[i][0], sol[i][1], i, radius);
}

int main(void) {
  // 2D inputs of the failing substep (cylinder-local x, y of p0, p1; the sidesite direction scaled to the radius), see wrapdiag.py
  const mjtNum end0[4] = {0.02050341146992268, 0.4443230385333684, 0.02536749714366278, -0.036176801386971186};
  const mjtNum side[2] = {0.02216969, -0.01155443};
  const mjtNum radius = 0.025;
  mjtNum pnt[4];
  printf("failing-substep inputs, no perturbation: ");
  for (CLAMP = 0; CLAMP < 2; CLAMP++) {
    mjtNum w = wrap_circle(pnt, end0, side, radius);
    printf("[clamp %d] wlen = %.17g (last dot %.17g)  ", CLAMP, w, g_last_dot);
  }
  printf("\n");
  // sweep: move p1's x by k * 1e-14 (k = -20000 .. 20000): the line passes through the tangent
  for (CLAMP = 0; CLAMP < 2; CLAMP++) {
    long nan = 0, wrap = 0, nowrap = 0, dot_gt1 = 0;
    for (long k = -20000; k <= 20000; k++) {
      mjtNum end[4] = {end0[0], end0[1], end0[2] - k * 1e-14, end0[3]};
      mjtNum w = wrap_circle(pnt, end, side, radius);
      if (w != w) nan++;
      else if (w < 0) nowrap++;
      else { wrap++; }
      if (w >= 0 || w != w) { if (g_last_dot > 1.0) dot_gt1++; }
    }
    printf("clamp %d: sweep of 40001 points: NaN %ld, wrap %ld (finite), no wrap %ld, points with dot > 1.0 before acos: %ld\n", CLAMP, nan, wrap, nowrap, dot_gt1);
  }
  return 0;
}
