// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
#include <metal_simdgroup_matrix>
using namespace metal;

// Threadgroup-wide reductions across up to 1024 threads (32 simdgroups).
inline float __tg_sum_f32(float v, threadgroup float *s, uint sl, uint si, uint n_simds) {
  float sm = simd_sum(v);
  if (sl == 0) { s[si] = sm; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float partial = (sl < n_simds) ? s[sl] : 0.0f;
  float total = (si == 0) ? simd_sum(partial) : 0.0f;
  if (si == 0 && sl == 0) { s[0] = total; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  return s[0];
}
inline float __tg_max_f32(float v, threadgroup float *s, uint sl, uint si, uint n_simds) {
  float sm = simd_max(v);
  if (sl == 0) { s[si] = sm; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float partial = (sl < n_simds) ? s[sl] : -INFINITY;
  float total = (si == 0) ? simd_max(partial) : -INFINITY;
  if (si == 0 && sl == 0) { s[0] = total; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  return s[0];
}
inline int __tg_min_i32(int v, threadgroup int *s, uint sl, uint si, uint n_simds) {
  int sm = simd_min(v);
  if (sl == 0) { s[si] = sm; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  int partial = (sl < n_simds) ? s[sl] : INT_MAX;
  int total = (si == 0) ? simd_min(partial) : INT_MAX;
  if (si == 0 && sl == 0) { s[0] = total; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  return s[0];
}

[[max_total_threads_per_threadgroup(1024)]]
kernel void c3_walk(
  device int *work_us [[buffer(0)]],
  device int *work_vs [[buffer(1)]],
  device int *work_ws [[buffer(2)]],
  device int *best_us [[buffer(3)]],
  device int *best_vs [[buffer(4)]],
  device int *best_ws [[buffer(5)]],
  device int *state_buf [[buffer(6)]],
  device int *seed_us [[buffer(7)]],
  device int *seed_vs [[buffer(8)]],
  device int *seed_ws [[buffer(9)]],
  device int *params [[buffer(10)]],
  uint3 __tid [[thread_position_in_grid]],
  uint3 __tid_in_tg [[thread_position_in_threadgroup]],
  uint3 __tg_id [[threadgroup_position_in_grid]],
  uint3 __tg_size [[threads_per_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  threadgroup float __tg_scratch_f[32];
  threadgroup int   __tg_scratch_i[32];
  uint __tg_total = __tg_size.x * __tg_size.y * __tg_size.z;
  int tid = int(__tid.x);
  int walkers = params[6];
  if ((tid < walkers)) {
    int nterms = params[0];
    int cap = params[1];
    int steps = params[2];
    int doinit = params[3];
    int band = params[4];
    int plusper = params[5];
    int seedden = params[7];
    int base = (tid * cap);
    int sb = (tid * 8);
    int rank = 0;
    int best = 0;
    int rng = 0;
    int bestden = 0;
    int attempts = 0;
    int partners = 0;
    int pluses = 0;
    int resets = 0;
    int step = 0;
    int i = 0;
    int ti = 0;
    int pj = 0;
    int axis = 0;
    int off = 0;
    int scan = 0;
    int jj = 0;
    int partner = -(1);
    int inorb = 0;
    int shared = 0;
    int phase = 0;
    int orbit = 0;
    int which = 0;
    int b = 0;
    int row = 0;
    int col = 0;
    int dst = 0;
    int found = -(1);
    int curden = 0;
    int capture = 0;
    int checkden = 0;
    int one = 1;
    int ui = 0;
    int vi = 0;
    int wi = 0;
    int uj = 0;
    int vj = 0;
    int wj = 0;
    int tui = 0;
    int tvi = 0;
    int twi = 0;
    int au = 0;
    int av2 = 0;
    int aw = 0;
    int bu = 0;
    int bv = 0;
    int bw = 0;
    int q = 0;
    int r = 0;
    int s = 0;
    int tq = 0;
    int trr = 0;
    int ts = 0;
    int x = 0;
    int y = 0;
    int z = 0;
    int pu = 0;
    int pv = 0;
    int pw = 0;
    int prime = 0;
    int second = 0;
    int px = 0;
    if ((doinit == 1)) {
      i = 0;
      while ((i < nterms)) {
        work_us[(base + i)] = seed_us[i];
        work_vs[(base + i)] = seed_vs[i];
        work_ws[(base + i)] = seed_ws[i];
        best_us[(base + i)] = seed_us[i];
        best_vs[(base + i)] = seed_vs[i];
        best_ws[(base + i)] = seed_ws[i];
        i = (i + 1);
      }
      state_buf[sb] = nterms;
      state_buf[(sb + 1)] = nterms;
      state_buf[(sb + 2)] = ((tid * 9973) + 12345);
      state_buf[(sb + 3)] = seedden;
      state_buf[(sb + 4)] = 0;
      state_buf[(sb + 5)] = 0;
      state_buf[(sb + 6)] = 0;
      state_buf[(sb + 7)] = 0;
    }
    rank = state_buf[sb];
    best = state_buf[(sb + 1)];
    rng = state_buf[(sb + 2)];
    bestden = state_buf[(sb + 3)];
    attempts = state_buf[(sb + 4)];
    partners = state_buf[(sb + 5)];
    pluses = state_buf[(sb + 6)];
    resets = state_buf[(sb + 7)];
    step = 0;
    while ((step < steps)) {
      attempts = (attempts + 1);
      rng = ((rng * 1103515245) + 12345);
      ti = (((rng % rank) + rank) % rank);
      ui = work_us[(base + ti)];
      vi = work_vs[(base + ti)];
      wi = work_ws[(base + ti)];
      tui = 0;
      tvi = 0;
      twi = 0;
      b = 0;
      while ((b < 9)) {
        row = (b / 3);
        col = (b % 3);
        dst = ((col * 3) + row);
        if ((((ui >> b) & one) == one)) {
          tui = (tui | (one << dst));
        }
        if ((((vi >> b) & one) == one)) {
          tvi = (tvi | (one << dst));
        }
        if ((((wi >> b) & one) == one)) {
          twi = (twi | (one << dst));
        }
        b = (b + 1);
      }
      rng = ((rng * 1103515245) + 12345);
      axis = (((rng % 3) + 3) % 3);
      rng = ((rng * 1103515245) + 12345);
      off = (((rng % rank) + rank) % rank);
      partner = -(1);
      scan = 0;
      while ((scan < rank)) {
        if ((partner < 0)) {
          jj = ((off + scan) % rank);
          if ((jj != ti)) {
            inorb = 0;
            if ((work_us[(base + jj)] == vi)) {
              if ((work_vs[(base + jj)] == twi)) {
                if ((work_ws[(base + jj)] == tui)) {
                  inorb = 1;
                }
              }
            }
            if ((work_us[(base + jj)] == twi)) {
              if ((work_vs[(base + jj)] == ui)) {
                if ((work_ws[(base + jj)] == tvi)) {
                  inorb = 1;
                }
              }
            }
            if ((inorb == 0)) {
              shared = 0;
              if ((axis == 0)) {
                if ((work_us[(base + jj)] == ui)) {
                  shared = 1;
                }
              }
              if ((axis == 1)) {
                if ((work_vs[(base + jj)] == vi)) {
                  shared = 1;
                }
              }
              if ((axis == 2)) {
                if ((work_ws[(base + jj)] == wi)) {
                  shared = 1;
                }
              }
              if ((shared == 1)) {
                partner = jj;
              }
            }
          }
        }
        scan = (scan + 1);
      }
      if ((partner >= 0)) {
        if ((rank <= (cap - 6))) {
          partners = (partners + 1);
          uj = work_us[(base + partner)];
          vj = work_vs[(base + partner)];
          wj = work_ws[(base + partner)];
          au = ui;
          av2 = vi;
          aw = wi;
          bu = ui;
          bv = vi;
          bw = wj;
          if ((axis == 0)) {
            aw = (wi ^ wj);
            bv = (vi ^ vj);
          }
          if ((axis == 1)) {
            aw = (wi ^ wj);
            bu = (ui ^ uj);
          }
          if ((axis == 2)) {
            av2 = (vi ^ vj);
            aw = wi;
            bu = (ui ^ uj);
            bv = vj;
            bw = wi;
          }
          phase = 0;
          while ((phase < 12)) {
            which = (phase / 3);
            orbit = (phase % 3);
            q = ui;
            r = vi;
            s = wi;
            if ((which == 1)) {
              q = uj;
              r = vj;
              s = wj;
            }
            if ((which == 2)) {
              q = au;
              r = av2;
              s = aw;
            }
            if ((which == 3)) {
              q = bu;
              r = bv;
              s = bw;
            }
            tq = 0;
            trr = 0;
            ts = 0;
            b = 0;
            while ((b < 9)) {
              row = (b / 3);
              col = (b % 3);
              dst = ((col * 3) + row);
              if ((((q >> b) & one) == one)) {
                tq = (tq | (one << dst));
              }
              if ((((r >> b) & one) == one)) {
                trr = (trr | (one << dst));
              }
              if ((((s >> b) & one) == one)) {
                ts = (ts | (one << dst));
              }
              b = (b + 1);
            }
            x = q;
            y = r;
            z = s;
            if ((orbit == 1)) {
              x = r;
              y = ts;
              z = tq;
            }
            if ((orbit == 2)) {
              x = ts;
              y = q;
              z = trr;
            }
            if ((x != 0)) {
              if ((y != 0)) {
                if ((z != 0)) {
                  found = -(1);
                  i = 0;
                  while ((i < rank)) {
                    if ((found < 0)) {
                      if ((work_us[(base + i)] == x)) {
                        if ((work_vs[(base + i)] == y)) {
                          if ((work_ws[(base + i)] == z)) {
                            found = i;
                          }
                        }
                      }
                    }
                    i = (i + 1);
                  }
                  if ((found >= 0)) {
                    rank = (rank - 1);
                    work_us[(base + found)] = work_us[(base + rank)];
                    work_vs[(base + found)] = work_vs[(base + rank)];
                    work_ws[(base + found)] = work_ws[(base + rank)];
                  }
                  if ((found < 0)) {
                    work_us[(base + rank)] = x;
                    work_vs[(base + rank)] = y;
                    work_ws[(base + rank)] = z;
                    rank = (rank + 1);
                  }
                }
              }
            }
            phase = (phase + 1);
          }
        }
      }
      if ((plusper > 0)) {
        if (((step % plusper) == 0)) {
          if ((rank <= (cap - 6))) {
            rng = ((rng * 1103515245) + 12345);
            ti = (((rng % rank) + rank) % rank);
            rng = ((rng * 1103515245) + 12345);
            pj = (((rng % rank) + rank) % rank);
            rng = ((rng * 1103515245) + 12345);
            axis = (((rng % 3) + 3) % 3);
            pu = work_us[(base + ti)];
            pv = work_vs[(base + ti)];
            pw = work_ws[(base + ti)];
            prime = work_us[(base + pj)];
            if ((axis == 1)) {
              prime = work_vs[(base + pj)];
            }
            if ((axis == 2)) {
              prime = work_ws[(base + pj)];
            }
            second = (pu ^ prime);
            if ((axis == 1)) {
              second = (pv ^ prime);
            }
            if ((axis == 2)) {
              second = (pw ^ prime);
            }
            if ((prime != 0)) {
              if ((second != 0)) {
                pluses = (pluses + 1);
                phase = 0;
                while ((phase < 9)) {
                  which = (phase / 3);
                  orbit = (phase % 3);
                  q = pu;
                  r = pv;
                  s = pw;
                  if ((axis == 0)) {
                    if ((which == 0)) {
                      q = prime;
                    }
                    if ((which == 1)) {
                      q = second;
                    }
                  }
                  if ((axis == 1)) {
                    if ((which == 0)) {
                      r = prime;
                    }
                    if ((which == 1)) {
                      r = second;
                    }
                  }
                  if ((axis == 2)) {
                    if ((which == 0)) {
                      s = prime;
                    }
                    if ((which == 1)) {
                      s = second;
                    }
                  }
                  tq = 0;
                  trr = 0;
                  ts = 0;
                  b = 0;
                  while ((b < 9)) {
                    row = (b / 3);
                    col = (b % 3);
                    dst = ((col * 3) + row);
                    if ((((q >> b) & one) == one)) {
                      tq = (tq | (one << dst));
                    }
                    if ((((r >> b) & one) == one)) {
                      trr = (trr | (one << dst));
                    }
                    if ((((s >> b) & one) == one)) {
                      ts = (ts | (one << dst));
                    }
                    b = (b + 1);
                  }
                  x = q;
                  y = r;
                  z = s;
                  if ((orbit == 1)) {
                    x = r;
                    y = ts;
                    z = tq;
                  }
                  if ((orbit == 2)) {
                    x = ts;
                    y = q;
                    z = trr;
                  }
                  if ((x != 0)) {
                    if ((y != 0)) {
                      if ((z != 0)) {
                        found = -(1);
                        i = 0;
                        while ((i < rank)) {
                          if ((found < 0)) {
                            if ((work_us[(base + i)] == x)) {
                              if ((work_vs[(base + i)] == y)) {
                                if ((work_ws[(base + i)] == z)) {
                                  found = i;
                                }
                              }
                            }
                          }
                          i = (i + 1);
                        }
                        if ((found >= 0)) {
                          rank = (rank - 1);
                          work_us[(base + found)] = work_us[(base + rank)];
                          work_vs[(base + found)] = work_vs[(base + rank)];
                          work_ws[(base + found)] = work_ws[(base + rank)];
                        }
                        if ((found < 0)) {
                          work_us[(base + rank)] = x;
                          work_vs[(base + rank)] = y;
                          work_ws[(base + rank)] = z;
                          rank = (rank + 1);
                        }
                      }
                    }
                  }
                  phase = (phase + 1);
                }
              }
            }
          }
        }
      }
      if ((rank > (best + band))) {
        i = 0;
        while ((i < best)) {
          work_us[(base + i)] = best_us[(base + i)];
          work_vs[(base + i)] = best_vs[(base + i)];
          work_ws[(base + i)] = best_ws[(base + i)];
          i = (i + 1);
        }
        rank = best;
        resets = (resets + 1);
      }
      capture = 0;
      checkden = 0;
      if ((rank < best)) {
        capture = 1;
        checkden = 1;
      }
      if ((rank == best)) {
        if (((step % 64) == 0)) {
          checkden = 1;
        }
      }
      if ((checkden == 1)) {
        curden = 0;
        i = 0;
        while ((i < rank)) {
          px = work_us[(base + i)];
          while ((px != 0)) {
            px = (px & (px - one));
            curden = (curden + 1);
          }
          px = work_vs[(base + i)];
          while ((px != 0)) {
            px = (px & (px - one));
            curden = (curden + 1);
          }
          px = work_ws[(base + i)];
          while ((px != 0)) {
            px = (px & (px - one));
            curden = (curden + 1);
          }
          i = (i + 1);
        }
        if ((rank == best)) {
          if ((curden < bestden)) {
            capture = 1;
          }
        }
      }
      if ((capture == 1)) {
        best = rank;
        bestden = curden;
        i = 0;
        while ((i < rank)) {
          best_us[(base + i)] = work_us[(base + i)];
          best_vs[(base + i)] = work_vs[(base + i)];
          best_ws[(base + i)] = work_ws[(base + i)];
          i = (i + 1);
        }
      }
      step = (step + 1);
    }
    state_buf[sb] = rank;
    state_buf[(sb + 1)] = best;
    state_buf[(sb + 2)] = rng;
    state_buf[(sb + 3)] = bestden;
    state_buf[(sb + 4)] = attempts;
    state_buf[(sb + 5)] = partners;
    state_buf[(sb + 6)] = pluses;
    state_buf[(sb + 7)] = resets;
  }
}

