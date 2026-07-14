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
kernel void flipwalk(
  device int *work_us [[buffer(0)]],
  device int *work_vs [[buffer(1)]],
  device int *work_ws [[buffer(2)]],
  device int *best_us [[buffer(3)]],
  device int *best_vs [[buffer(4)]],
  device int *best_ws [[buffer(5)]],
  device int *st [[buffer(6)]],
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
  int ltid = int(__tid_in_tg.x);
  int nterms = params[0];
  int cap = params[1];
  int steps = params[2];
  int doinit = params[3];
  int margin = params[4];
  int wqwork = params[5];
  int wqwander = params[6];
  int wthr0 = params[7];
  int firstinit = params[8];
  int nseeds = params[9];
  int seedstride = params[10];
  int base = (tid * cap);
  int sb = (tid * 9);
  int seedid = (tid % nseeds);
  int seedbase = (seedid * seedstride);
  threadgroup int sus[1232];
  threadgroup int svs[1232];
  threadgroup int sws[1232];
  int i = 0;
  int rank = 0;
  int best = 0;
  int state = 0;
  int aband = 0;
  int wthr = 0;
  int wraps = 0;
  int mv = 0;
  int nextesc = 0;
  int step = 0;
  int roll = 0;
  int didplus = 0;
  int pt = 0;
  int u1 = 0;
  int fi = 0;
  int axis = 0;
  int off = 0;
  int fj = 0;
  int scan = 0;
  int cand = 0;
  int t = 0;
  int z = 0;
  int a = 0;
  int bb = 0;
  int dup = 0;
  int ci = 0;
  int dchk = 0;
  int pb = 0;
  int paxis = 0;
  int nb = 0;
  int bestden = 0;
  int dsum = 0;
  int capit = 0;
  int docap = 0;
  int pz = 0;
  if ((doinit == 1)) {
    i = 0;
    while ((i < nterms)) {
      sus[((i * 16) + ltid)] = seed_us[(seedbase + i)];
      svs[((i * 16) + ltid)] = seed_vs[(seedbase + i)];
      sws[((i * 16) + ltid)] = seed_ws[(seedbase + i)];
      best_us[(base + i)] = seed_us[(seedbase + i)];
      best_vs[(base + i)] = seed_vs[(seedbase + i)];
      best_ws[(base + i)] = seed_ws[(seedbase + i)];
      i = (i + 1);
    }
    st[sb] = nterms;
    st[(sb + 1)] = nterms;
    st[(sb + 2)] = ((tid * 9973) + 12345);
  }
  if ((firstinit == 1)) {
    st[(sb + 3)] = 1;
    st[(sb + 4)] = wthr0;
    st[(sb + 5)] = 0;
    st[(sb + 6)] = 0;
    st[(sb + 7)] = wqwork;
    st[(sb + 8)] = 999999;
  }
  rank = st[sb];
  best = st[(sb + 1)];
  state = st[(sb + 2)];
  aband = st[(sb + 3)];
  wthr = st[(sb + 4)];
  wraps = st[(sb + 5)];
  mv = st[(sb + 6)];
  nextesc = st[(sb + 7)];
  bestden = st[(sb + 8)];
  if ((doinit == 0)) {
    i = 0;
    while ((i < rank)) {
      sus[((i * 16) + ltid)] = work_us[(base + i)];
      svs[((i * 16) + ltid)] = work_vs[(base + i)];
      sws[((i * 16) + ltid)] = work_ws[(base + i)];
      i = (i + 1);
    }
  }
  step = 0;
  while ((step < steps)) {
    mv = (mv + 1);
    state = ((state * 1103515245) + 12345);
    roll = (((state % 6) + 6) % 6);
    didplus = 0;
    if ((roll == 0)) {
      if ((rank < (best + margin))) {
        if ((rank < (cap - 1))) {
          state = ((state * 1103515245) + 12345);
          pt = (((state % rank) + rank) % rank);
          state = ((state * 1103515245) + 12345);
          u1 = ((((state % 32767) + 32767) % 32767) + 1);
          state = ((state * 1103515245) + 12345);
          paxis = (((state % 3) + 3) % 3);
          if ((paxis == 0)) {
            u1 = (u1 & 511);
          }
          if ((paxis == 1)) {
            u1 = (u1 & 32767);
          }
          if ((paxis == 2)) {
            u1 = (u1 & 32767);
          }
          if ((u1 == 0)) {
            u1 = 1;
          }
          pb = ((pt * 16) + ltid);
          if ((paxis == 0)) {
            if ((u1 != sus[pb])) {
              sus[((rank * 16) + ltid)] = (sus[pb] ^ u1);
              svs[((rank * 16) + ltid)] = svs[pb];
              sws[((rank * 16) + ltid)] = sws[pb];
              sus[pb] = u1;
              rank = (rank + 1);
              didplus = 1;
            }
          }
          if ((paxis == 1)) {
            if ((u1 != svs[pb])) {
              svs[((rank * 16) + ltid)] = (svs[pb] ^ u1);
              sus[((rank * 16) + ltid)] = sus[pb];
              sws[((rank * 16) + ltid)] = sws[pb];
              svs[pb] = u1;
              rank = (rank + 1);
              didplus = 1;
            }
          }
          if ((paxis == 2)) {
            if ((u1 != sws[pb])) {
              sws[((rank * 16) + ltid)] = (sws[pb] ^ u1);
              sus[((rank * 16) + ltid)] = sus[pb];
              svs[((rank * 16) + ltid)] = svs[pb];
              sws[pb] = u1;
              rank = (rank + 1);
              didplus = 1;
            }
          }
        }
      }
    }
    if ((didplus == 0)) {
      state = ((state * 1103515245) + 12345);
      fi = (((state % rank) + rank) % rank);
      state = ((state * 1103515245) + 12345);
      axis = (((state % 3) + 3) % 3);
      state = ((state * 1103515245) + 12345);
      off = (((state % rank) + rank) % rank);
      fj = -(1);
      scan = 0;
      while ((scan < rank)) {
        if ((fj < 0)) {
          cand = ((off + scan) % rank);
          if ((cand != fi)) {
            if ((axis == 0)) {
              if ((sus[((cand * 16) + ltid)] == sus[((fi * 16) + ltid)])) {
                fj = cand;
              }
            }
            if ((axis == 1)) {
              if ((svs[((cand * 16) + ltid)] == svs[((fi * 16) + ltid)])) {
                fj = cand;
              }
            }
            if ((axis == 2)) {
              if ((sws[((cand * 16) + ltid)] == sws[((fi * 16) + ltid)])) {
                fj = cand;
              }
            }
          }
        }
        scan = (scan + 1);
      }
      if ((fj >= 0)) {
        if ((axis == 0)) {
          sws[((fi * 16) + ltid)] = (sws[((fi * 16) + ltid)] ^ sws[((fj * 16) + ltid)]);
          svs[((fj * 16) + ltid)] = (svs[((fi * 16) + ltid)] ^ svs[((fj * 16) + ltid)]);
        }
        if ((axis == 1)) {
          sws[((fi * 16) + ltid)] = (sws[((fi * 16) + ltid)] ^ sws[((fj * 16) + ltid)]);
          sus[((fj * 16) + ltid)] = (sus[((fi * 16) + ltid)] ^ sus[((fj * 16) + ltid)]);
        }
        if ((axis == 2)) {
          svs[((fi * 16) + ltid)] = (svs[((fi * 16) + ltid)] ^ svs[((fj * 16) + ltid)]);
          sus[((fj * 16) + ltid)] = (sus[((fi * 16) + ltid)] ^ sus[((fj * 16) + ltid)]);
        }
      }
    }
    t = 0;
    while ((t < rank)) {
      z = 0;
      if ((sus[((t * 16) + ltid)] == 0)) {
        z = 1;
      }
      if ((svs[((t * 16) + ltid)] == 0)) {
        z = 1;
      }
      if ((sws[((t * 16) + ltid)] == 0)) {
        z = 1;
      }
      if ((z == 1)) {
        sus[((t * 16) + ltid)] = sus[(((rank - 1) * 16) + ltid)];
        svs[((t * 16) + ltid)] = svs[(((rank - 1) * 16) + ltid)];
        sws[((t * 16) + ltid)] = sws[(((rank - 1) * 16) + ltid)];
        rank = (rank - 1);
      }
      if ((z == 0)) {
        t = (t + 1);
      }
    }
    if ((didplus == 1)) {
      a = (rank - 1);
      if ((a >= 0)) {
        dup = -(1);
        bb = 0;
        while ((bb < a)) {
          if ((dup < 0)) {
            if ((sus[((a * 16) + ltid)] == sus[((bb * 16) + ltid)])) {
              if ((svs[((a * 16) + ltid)] == svs[((bb * 16) + ltid)])) {
                if ((sws[((a * 16) + ltid)] == sws[((bb * 16) + ltid)])) {
                  dup = bb;
                }
              }
            }
          }
          bb = (bb + 1);
        }
        if ((dup >= 0)) {
          sus[((dup * 16) + ltid)] = sus[(((rank - 1) * 16) + ltid)];
          svs[((dup * 16) + ltid)] = svs[(((rank - 1) * 16) + ltid)];
          sws[((dup * 16) + ltid)] = sws[(((rank - 1) * 16) + ltid)];
          rank = (rank - 1);
          sus[((a * 16) + ltid)] = sus[(((rank - 1) * 16) + ltid)];
          svs[((a * 16) + ltid)] = svs[(((rank - 1) * 16) + ltid)];
          sws[((a * 16) + ltid)] = sws[(((rank - 1) * 16) + ltid)];
          rank = (rank - 1);
        }
      }
    }
    if ((didplus == 0)) {
      a = fi;
      if ((a < rank)) {
        dup = -(1);
        bb = 0;
        while ((bb < rank)) {
          if ((dup < 0)) {
            if ((bb != a)) {
              if ((sus[((a * 16) + ltid)] == sus[((bb * 16) + ltid)])) {
                if ((svs[((a * 16) + ltid)] == svs[((bb * 16) + ltid)])) {
                  if ((sws[((a * 16) + ltid)] == sws[((bb * 16) + ltid)])) {
                    dup = bb;
                  }
                }
              }
            }
          }
          bb = (bb + 1);
        }
        if ((dup >= 0)) {
          sus[((dup * 16) + ltid)] = sus[(((rank - 1) * 16) + ltid)];
          svs[((dup * 16) + ltid)] = svs[(((rank - 1) * 16) + ltid)];
          sws[((dup * 16) + ltid)] = sws[(((rank - 1) * 16) + ltid)];
          rank = (rank - 1);
          sus[((a * 16) + ltid)] = sus[(((rank - 1) * 16) + ltid)];
          svs[((a * 16) + ltid)] = svs[(((rank - 1) * 16) + ltid)];
          sws[((a * 16) + ltid)] = sws[(((rank - 1) * 16) + ltid)];
          rank = (rank - 1);
        }
      }
      a = fj;
      if ((a < rank)) {
        dup = -(1);
        bb = 0;
        while ((bb < rank)) {
          if ((dup < 0)) {
            if ((bb != a)) {
              if ((sus[((a * 16) + ltid)] == sus[((bb * 16) + ltid)])) {
                if ((svs[((a * 16) + ltid)] == svs[((bb * 16) + ltid)])) {
                  if ((sws[((a * 16) + ltid)] == sws[((bb * 16) + ltid)])) {
                    dup = bb;
                  }
                }
              }
            }
          }
          bb = (bb + 1);
        }
        if ((dup >= 0)) {
          sus[((dup * 16) + ltid)] = sus[(((rank - 1) * 16) + ltid)];
          svs[((dup * 16) + ltid)] = svs[(((rank - 1) * 16) + ltid)];
          sws[((dup * 16) + ltid)] = sws[(((rank - 1) * 16) + ltid)];
          rank = (rank - 1);
          sus[((a * 16) + ltid)] = sus[(((rank - 1) * 16) + ltid)];
          svs[((a * 16) + ltid)] = svs[(((rank - 1) * 16) + ltid)];
          sws[((a * 16) + ltid)] = sws[(((rank - 1) * 16) + ltid)];
          rank = (rank - 1);
        }
      }
    }
    dchk = (step % 4096);
    if ((dchk == 0)) {
      a = 0;
      while ((a < rank)) {
        dup = -(1);
        bb = (a + 1);
        while ((bb < rank)) {
          if ((dup < 0)) {
            if ((sus[((a * 16) + ltid)] == sus[((bb * 16) + ltid)])) {
              if ((svs[((a * 16) + ltid)] == svs[((bb * 16) + ltid)])) {
                if ((sws[((a * 16) + ltid)] == sws[((bb * 16) + ltid)])) {
                  dup = bb;
                }
              }
            }
          }
          bb = (bb + 1);
        }
        if ((dup >= 0)) {
          sus[((dup * 16) + ltid)] = sus[(((rank - 1) * 16) + ltid)];
          svs[((dup * 16) + ltid)] = svs[(((rank - 1) * 16) + ltid)];
          sws[((dup * 16) + ltid)] = sws[(((rank - 1) * 16) + ltid)];
          rank = (rank - 1);
          sus[((a * 16) + ltid)] = sus[(((rank - 1) * 16) + ltid)];
          svs[((a * 16) + ltid)] = svs[(((rank - 1) * 16) + ltid)];
          sws[((a * 16) + ltid)] = sws[(((rank - 1) * 16) + ltid)];
          rank = (rank - 1);
        }
        if ((dup < 0)) {
          a = (a + 1);
        }
      }
    }
    docap = 0;
    if ((rank < best)) {
      docap = 1;
    }
    if ((rank == best)) {
      if (((step % 64) == 0)) {
        docap = 1;
      }
    }
    if ((docap == 1)) {
      dsum = 0;
      ci = 0;
      while ((ci < rank)) {
        pz = sus[((ci * 16) + ltid)];
        while ((pz != 0)) {
          pz = (pz & (pz - 1));
          dsum = (dsum + 1);
        }
        pz = svs[((ci * 16) + ltid)];
        while ((pz != 0)) {
          pz = (pz & (pz - 1));
          dsum = (dsum + 1);
        }
        pz = sws[((ci * 16) + ltid)];
        while ((pz != 0)) {
          pz = (pz & (pz - 1));
          dsum = (dsum + 1);
        }
        ci = (ci + 1);
      }
      capit = 0;
      if ((rank < best)) {
        capit = 1;
      }
      if ((rank == best)) {
        if ((dsum < bestden)) {
          capit = 1;
        }
      }
      if ((capit == 1)) {
        best = rank;
        bestden = dsum;
        ci = 0;
        while ((ci < rank)) {
          best_us[(base + ci)] = sus[((ci * 16) + ltid)];
          best_vs[(base + ci)] = svs[((ci * 16) + ltid)];
          best_ws[(base + ci)] = sws[((ci * 16) + ltid)];
          ci = (ci + 1);
        }
        if (((aband + 1) > wthr)) {
          wthr = (aband + 1);
        }
        aband = 1;
      }
    }
    if ((mv >= nextesc)) {
      nb = (aband + 1);
      if ((aband > wthr)) {
        nb = (aband + 12);
      }
      if ((nb > 60)) {
        nb = 1;
        wraps = (wraps + 1);
        if ((wraps >= 2)) {
          wraps = 0;
          state = ((((state ^ (mv & 2147483647)) * 1103515245) + 54321) & 2147483647);
          state = ((state * 1103515245) + 12345);
          state = ((state * 1103515245) + 12345);
          i = 0;
          while ((i < nterms)) {
            sus[((i * 16) + ltid)] = seed_us[(seedbase + i)];
            svs[((i * 16) + ltid)] = seed_vs[(seedbase + i)];
            sws[((i * 16) + ltid)] = seed_ws[(seedbase + i)];
            i = (i + 1);
          }
          rank = nterms;
          best = nterms;
          bestden = 999999;
          ci = 0;
          while ((ci < nterms)) {
            best_us[(base + ci)] = seed_us[(seedbase + ci)];
            best_vs[(base + ci)] = seed_vs[(seedbase + ci)];
            best_ws[(base + ci)] = seed_ws[(seedbase + ci)];
            ci = (ci + 1);
          }
        }
      }
      aband = nb;
      if ((aband > wthr)) {
        nextesc = (mv + wqwander);
      }
      if ((aband <= wthr)) {
        nextesc = (mv + wqwork);
      }
    }
    step = (step + 1);
  }
  i = 0;
  while ((i < rank)) {
    work_us[(base + i)] = sus[((i * 16) + ltid)];
    work_vs[(base + i)] = svs[((i * 16) + ltid)];
    work_ws[(base + i)] = sws[((i * 16) + ltid)];
    i = (i + 1);
  }
  st[sb] = rank;
  st[(sb + 1)] = best;
  st[(sb + 2)] = state;
  st[(sb + 3)] = aband;
  st[(sb + 4)] = wthr;
  st[(sb + 5)] = wraps;
  st[(sb + 6)] = mv;
  st[(sb + 7)] = nextesc;
  st[(sb + 8)] = bestden;
}

