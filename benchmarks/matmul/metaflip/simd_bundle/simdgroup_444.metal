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
kernel void flipwalk_simd(
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
  int gid = int(__tg_id.x);
  int lane = int(__simd_lane);
  int nterms = params[0];
  int cap = params[1];
  int steps = params[2];
  int doinit = params[3];
  int margin = params[4];
  int seedden = params[5];
  int mode = params[6];
  int base = (gid * cap);
  int sb = (gid * 8);
  threadgroup int sus[80];
  threadgroup int svs[80];
  threadgroup int sws[80];
  threadgroup int schanged[6];
  threadgroup int heads[768];
  threadgroup int nexts[240];
  int i = lane;
  int rank = 0;
  int best = 0;
  int state = 0;
  int bestden = 0;
  int attempts = 0;
  int partners = 0;
  int captures = 0;
  int step = 0;
  int roll = 0;
  int didplus = 0;
  int pt = 0;
  int part = 0;
  int fi = 0;
  int fj = -(1);
  int axis = 0;
  int off = 0;
  int cand = 0;
  int scan = 0;
  int localmin = 0;
  int bestdist = 0;
  int t = 0;
  int m1 = 0;
  int m2 = 0;
  int zi = 0;
  int hi = 0;
  int lo = 0;
  int last = 0;
  int have1 = 0;
  int have2 = 0;
  int cu1 = 0;
  int cv1 = 0;
  int cw1 = 0;
  int cu2 = 0;
  int cv2 = 0;
  int cw2 = 0;
  int localden = 0;
  int dsum = 0;
  int px = 0;
  int capture = 0;
  int hashedrank = 0;
  int buildaxis = 0;
  int update = 0;
  int updidx = 0;
  int updaxis = 0;
  int hashslot = 0;
  int headslot = 0;
  int cur = 0;
  int prev = 0;
  int nxt = 0;
  int oldfactor = 0;
  if ((doinit == 1)) {
    i = lane;
    while ((i < nterms)) {
      sus[i] = seed_us[i];
      svs[i] = seed_vs[i];
      sws[i] = seed_ws[i];
      best_us[(base + i)] = seed_us[i];
      best_vs[(base + i)] = seed_vs[i];
      best_ws[(base + i)] = seed_ws[i];
      i = (i + 32);
    }
    if ((lane == 0)) {
      st[sb] = nterms;
      st[(sb + 1)] = nterms;
      st[(sb + 2)] = ((gid * 9973) + 12345);
      st[(sb + 3)] = seedden;
      st[(sb + 4)] = 0;
      st[(sb + 5)] = 0;
      st[(sb + 6)] = 0;
      st[(sb + 7)] = 0;
    }
  }
  if ((doinit == 0)) {
    if ((lane == 0)) {
      rank = st[sb];
    }
    rank = simd_broadcast_first(rank);
    i = lane;
    while ((i < rank)) {
      sus[i] = work_us[(base + i)];
      svs[i] = work_vs[(base + i)];
      sws[i] = work_ws[(base + i)];
      i = (i + 32);
    }
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  if ((lane == 0)) {
    rank = st[sb];
    best = st[(sb + 1)];
    state = st[(sb + 2)];
    bestden = st[(sb + 3)];
    attempts = st[(sb + 4)];
    partners = st[(sb + 5)];
    captures = st[(sb + 6)];
  }
  rank = simd_broadcast_first(rank);
  best = simd_broadcast_first(best);
  state = simd_broadcast_first(state);
  bestden = simd_broadcast_first(bestden);
  attempts = simd_broadcast_first(attempts);
  partners = simd_broadcast_first(partners);
  captures = simd_broadcast_first(captures);
  if ((mode == 1)) {
    i = lane;
    while ((i < 768)) {
      heads[i] = -(1);
      i = (i + 32);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if ((lane == 0)) {
      buildaxis = 0;
      while ((buildaxis < 3)) {
        i = 0;
        while ((i < rank)) {
          oldfactor = sus[i];
          if ((buildaxis == 1)) {
            oldfactor = svs[i];
          }
          if ((buildaxis == 2)) {
            oldfactor = sws[i];
          }
          hashslot = (((oldfactor ^ (oldfactor >> 11)) ^ (oldfactor >> 23)) & 255);
          headslot = ((buildaxis * 256) + hashslot);
          nexts[((buildaxis * cap) + i)] = heads[headslot];
          heads[headslot] = i;
          i = (i + 1);
        }
        buildaxis = (buildaxis + 1);
      }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }
  step = 0;
  while ((step < steps)) {
    if ((lane == 0)) {
      attempts = (attempts + 1);
      state = ((state * 1103515245) + 12345);
      roll = (((state % 6) + 6) % 6);
      didplus = 0;
      have1 = 0;
      have2 = 0;
      if ((roll == 0)) {
        if ((rank < (best + margin))) {
          if ((rank < cap)) {
            state = ((state * 1103515245) + 12345);
            pt = (((state % rank) + rank) % rank);
            state = ((state * 1103515245) + 12345);
            part = ((((state % 65535) + 65535) % 65535) + 1);
            state = ((state * 1103515245) + 12345);
            axis = (((state % 3) + 3) % 3);
            oldfactor = sus[pt];
            if ((axis == 1)) {
              oldfactor = svs[pt];
            }
            if ((axis == 2)) {
              oldfactor = sws[pt];
            }
            if ((part != oldfactor)) {
              if ((mode == 1)) {
                hashslot = (((oldfactor ^ (oldfactor >> 11)) ^ (oldfactor >> 23)) & 255);
                headslot = ((axis * 256) + hashslot);
                cur = heads[headslot];
                prev = -(1);
                while ((cur >= 0)) {
                  nxt = nexts[((axis * cap) + cur)];
                  if ((cur == pt)) {
                    if ((prev < 0)) {
                      heads[headslot] = nxt;
                    }
                    if ((prev >= 0)) {
                      nexts[((axis * cap) + prev)] = nxt;
                    }
                    cur = -(1);
                  }
                  if ((cur >= 0)) {
                    prev = cur;
                    cur = nxt;
                  }
                }
              }
              if ((axis == 0)) {
                sus[rank] = (sus[pt] ^ part);
                svs[rank] = svs[pt];
                sws[rank] = sws[pt];
                sus[pt] = part;
              }
              if ((axis == 1)) {
                svs[rank] = (svs[pt] ^ part);
                sus[rank] = sus[pt];
                sws[rank] = sws[pt];
                svs[pt] = part;
              }
              if ((axis == 2)) {
                sws[rank] = (sws[pt] ^ part);
                sus[rank] = sus[pt];
                svs[rank] = svs[pt];
                sws[pt] = part;
              }
              if ((mode == 1)) {
                oldfactor = sus[pt];
                if ((axis == 1)) {
                  oldfactor = svs[pt];
                }
                if ((axis == 2)) {
                  oldfactor = sws[pt];
                }
                hashslot = (((oldfactor ^ (oldfactor >> 11)) ^ (oldfactor >> 23)) & 255);
                headslot = ((axis * 256) + hashslot);
                nexts[((axis * cap) + pt)] = heads[headslot];
                heads[headslot] = pt;
                buildaxis = 0;
                while ((buildaxis < 3)) {
                  oldfactor = sus[rank];
                  if ((buildaxis == 1)) {
                    oldfactor = svs[rank];
                  }
                  if ((buildaxis == 2)) {
                    oldfactor = sws[rank];
                  }
                  hashslot = (((oldfactor ^ (oldfactor >> 11)) ^ (oldfactor >> 23)) & 255);
                  headslot = ((buildaxis * 256) + hashslot);
                  nexts[((buildaxis * cap) + rank)] = heads[headslot];
                  heads[headslot] = rank;
                  buildaxis = (buildaxis + 1);
                }
              }
              cu1 = sus[pt];
              cv1 = svs[pt];
              cw1 = sws[pt];
              cu2 = sus[rank];
              cv2 = svs[rank];
              cw2 = sws[rank];
              rank = (rank + 1);
              didplus = 1;
            }
            if ((didplus == 1)) {
              have1 = 1;
              have2 = 1;
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
      }
    }
    rank = simd_broadcast_first(rank);
    best = simd_broadcast_first(best);
    state = simd_broadcast_first(state);
    attempts = simd_broadcast_first(attempts);
    roll = simd_broadcast_first(roll);
    didplus = simd_broadcast_first(didplus);
    fi = simd_broadcast_first(fi);
    axis = simd_broadcast_first(axis);
    off = simd_broadcast_first(off);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if ((didplus == 0)) {
      localmin = 2147483647;
      fj = -(1);
      if ((mode == 0)) {
        scan = lane;
        while ((scan < rank)) {
          cand = ((off + scan) % rank);
          if ((cand != fi)) {
            if ((axis == 0)) {
              if ((sus[cand] == sus[fi])) {
                if ((scan < localmin)) {
                  localmin = scan;
                }
              }
            }
            if ((axis == 1)) {
              if ((svs[cand] == svs[fi])) {
                if ((scan < localmin)) {
                  localmin = scan;
                }
              }
            }
            if ((axis == 2)) {
              if ((sws[cand] == sws[fi])) {
                if ((scan < localmin)) {
                  localmin = scan;
                }
              }
            }
          }
          scan = (scan + 32);
        }
        bestdist = simd_min(localmin);
        if ((bestdist < 2147483647)) {
          fj = ((off + bestdist) % rank);
        }
      }
      if ((mode == 1)) {
        if ((lane == 0)) {
          oldfactor = sus[fi];
          if ((axis == 1)) {
            oldfactor = svs[fi];
          }
          if ((axis == 2)) {
            oldfactor = sws[fi];
          }
          hashslot = (((oldfactor ^ (oldfactor >> 11)) ^ (oldfactor >> 23)) & 255);
          cur = heads[((axis * 256) + hashslot)];
          while ((cur >= 0)) {
            if ((cur != fi)) {
              cand = 0;
              if ((axis == 0)) {
                if ((sus[cur] == oldfactor)) {
                  cand = 1;
                }
              }
              if ((axis == 1)) {
                if ((svs[cur] == oldfactor)) {
                  cand = 1;
                }
              }
              if ((axis == 2)) {
                if ((sws[cur] == oldfactor)) {
                  cand = 1;
                }
              }
              if ((cand == 1)) {
                scan = (((cur - off) + rank) % rank);
                if ((scan < localmin)) {
                  localmin = scan;
                  fj = cur;
                }
              }
            }
            cur = nexts[((axis * cap) + cur)];
          }
        }
        fj = simd_broadcast_first(fj);
      }
      if ((lane == 0)) {
        if ((fj >= 0)) {
          partners = (partners + 1);
          if ((mode == 1)) {
            update = 0;
            while ((update < 2)) {
              updidx = fi;
              updaxis = 2;
              if ((update == 1)) {
                updidx = fj;
                updaxis = 1;
              }
              if ((axis == 1)) {
                if ((update == 1)) {
                  updaxis = 0;
                }
              }
              if ((axis == 2)) {
                if ((update == 0)) {
                  updaxis = 1;
                }
                if ((update == 1)) {
                  updaxis = 0;
                }
              }
              oldfactor = sus[updidx];
              if ((updaxis == 1)) {
                oldfactor = svs[updidx];
              }
              if ((updaxis == 2)) {
                oldfactor = sws[updidx];
              }
              hashslot = (((oldfactor ^ (oldfactor >> 11)) ^ (oldfactor >> 23)) & 255);
              headslot = ((updaxis * 256) + hashslot);
              cur = heads[headslot];
              prev = -(1);
              while ((cur >= 0)) {
                nxt = nexts[((updaxis * cap) + cur)];
                if ((cur == updidx)) {
                  if ((prev < 0)) {
                    heads[headslot] = nxt;
                  }
                  if ((prev >= 0)) {
                    nexts[((updaxis * cap) + prev)] = nxt;
                  }
                  cur = -(1);
                }
                if ((cur >= 0)) {
                  prev = cur;
                  cur = nxt;
                }
              }
              update = (update + 1);
            }
          }
          if ((axis == 0)) {
            sws[fi] = (sws[fi] ^ sws[fj]);
            svs[fj] = (svs[fi] ^ svs[fj]);
          }
          if ((axis == 1)) {
            sws[fi] = (sws[fi] ^ sws[fj]);
            sus[fj] = (sus[fi] ^ sus[fj]);
          }
          if ((axis == 2)) {
            svs[fi] = (svs[fi] ^ svs[fj]);
            sus[fj] = (sus[fi] ^ sus[fj]);
          }
          if ((mode == 1)) {
            update = 0;
            while ((update < 2)) {
              updidx = fi;
              updaxis = 2;
              if ((update == 1)) {
                updidx = fj;
                updaxis = 1;
              }
              if ((axis == 1)) {
                if ((update == 1)) {
                  updaxis = 0;
                }
              }
              if ((axis == 2)) {
                if ((update == 0)) {
                  updaxis = 1;
                }
                if ((update == 1)) {
                  updaxis = 0;
                }
              }
              oldfactor = sus[updidx];
              if ((updaxis == 1)) {
                oldfactor = svs[updidx];
              }
              if ((updaxis == 2)) {
                oldfactor = sws[updidx];
              }
              hashslot = (((oldfactor ^ (oldfactor >> 11)) ^ (oldfactor >> 23)) & 255);
              headslot = ((updaxis * 256) + hashslot);
              nexts[((updaxis * cap) + updidx)] = heads[headslot];
              heads[headslot] = updidx;
              update = (update + 1);
            }
          }
          cu1 = sus[fi];
          cv1 = svs[fi];
          cw1 = sws[fi];
          cu2 = sus[fj];
          cv2 = svs[fj];
          cw2 = sws[fj];
          have1 = 1;
          have2 = 1;
        }
      }
    }
    if ((lane == 0)) {
      schanged[0] = cu1;
      schanged[1] = cv1;
      schanged[2] = cw1;
      schanged[3] = cu2;
      schanged[4] = cv2;
      schanged[5] = cw2;
    }
    partners = simd_broadcast_first(partners);
    have1 = simd_broadcast_first(have1);
    have2 = simd_broadcast_first(have2);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    cu1 = schanged[0];
    cv1 = schanged[1];
    cw1 = schanged[2];
    cu2 = schanged[3];
    cv2 = schanged[4];
    cw2 = schanged[5];
    hashedrank = rank;
    hashedrank = simd_broadcast_first(hashedrank);
    if ((have1 == 1)) {
      if ((cu1 != 0)) {
        if ((cv1 != 0)) {
          if ((cw1 != 0)) {
            localmin = cap;
            t = lane;
            while ((t < rank)) {
              if ((sus[t] == cu1)) {
                if ((svs[t] == cv1)) {
                  if ((sws[t] == cw1)) {
                    if ((t < localmin)) {
                      localmin = t;
                    }
                  }
                }
              }
              t = (t + 32);
            }
            m1 = simd_min(localmin);
            localmin = cap;
            t = lane;
            while ((t < rank)) {
              if ((t != m1)) {
                if ((sus[t] == cu1)) {
                  if ((svs[t] == cv1)) {
                    if ((sws[t] == cw1)) {
                      if ((t < localmin)) {
                        localmin = t;
                      }
                    }
                  }
                }
              }
              t = (t + 32);
            }
            m2 = simd_min(localmin);
            if ((lane == 0)) {
              if ((m2 < rank)) {
                hi = m1;
                lo = m2;
                if ((lo > hi)) {
                  hi = m2;
                  lo = m1;
                }
                last = (rank - 1);
                if ((hi != last)) {
                  sus[hi] = sus[last];
                  svs[hi] = svs[last];
                  sws[hi] = sws[last];
                }
                rank = (rank - 1);
                last = (rank - 1);
                if ((lo != last)) {
                  sus[lo] = sus[last];
                  svs[lo] = svs[last];
                  sws[lo] = sws[last];
                }
                rank = (rank - 1);
              }
            }
            rank = simd_broadcast_first(rank);
            threadgroup_barrier(mem_flags::mem_threadgroup);
          }
        }
      }
    }
    if ((have2 == 1)) {
      if ((cu2 != 0)) {
        if ((cv2 != 0)) {
          if ((cw2 != 0)) {
            localmin = cap;
            t = lane;
            while ((t < rank)) {
              if ((sus[t] == cu2)) {
                if ((svs[t] == cv2)) {
                  if ((sws[t] == cw2)) {
                    if ((t < localmin)) {
                      localmin = t;
                    }
                  }
                }
              }
              t = (t + 32);
            }
            m1 = simd_min(localmin);
            localmin = cap;
            t = lane;
            while ((t < rank)) {
              if ((t != m1)) {
                if ((sus[t] == cu2)) {
                  if ((svs[t] == cv2)) {
                    if ((sws[t] == cw2)) {
                      if ((t < localmin)) {
                        localmin = t;
                      }
                    }
                  }
                }
              }
              t = (t + 32);
            }
            m2 = simd_min(localmin);
            if ((lane == 0)) {
              if ((m2 < rank)) {
                hi = m1;
                lo = m2;
                if ((lo > hi)) {
                  hi = m2;
                  lo = m1;
                }
                last = (rank - 1);
                if ((hi != last)) {
                  sus[hi] = sus[last];
                  svs[hi] = svs[last];
                  sws[hi] = sws[last];
                }
                rank = (rank - 1);
                last = (rank - 1);
                if ((lo != last)) {
                  sus[lo] = sus[last];
                  svs[lo] = svs[last];
                  sws[lo] = sws[last];
                }
                rank = (rank - 1);
              }
            }
            rank = simd_broadcast_first(rank);
            threadgroup_barrier(mem_flags::mem_threadgroup);
          }
        }
      }
    }
    zi = 0;
    while ((zi < rank)) {
      localmin = cap;
      t = lane;
      while ((t < rank)) {
        if ((sus[t] == 0)) {
          if ((t < localmin)) {
            localmin = t;
          }
        }
        if ((svs[t] == 0)) {
          if ((t < localmin)) {
            localmin = t;
          }
        }
        if ((sws[t] == 0)) {
          if ((t < localmin)) {
            localmin = t;
          }
        }
        t = (t + 32);
      }
      zi = simd_min(localmin);
      if ((lane == 0)) {
        if ((zi < rank)) {
          last = (rank - 1);
          if ((zi != last)) {
            sus[zi] = sus[last];
            svs[zi] = svs[last];
            sws[zi] = sws[last];
          }
          rank = (rank - 1);
        }
      }
      rank = simd_broadcast_first(rank);
      threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if ((mode == 1)) {
      if ((rank != hashedrank)) {
        i = lane;
        while ((i < 768)) {
          heads[i] = -(1);
          i = (i + 32);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        if ((lane == 0)) {
          buildaxis = 0;
          while ((buildaxis < 3)) {
            i = 0;
            while ((i < rank)) {
              oldfactor = sus[i];
              if ((buildaxis == 1)) {
                oldfactor = svs[i];
              }
              if ((buildaxis == 2)) {
                oldfactor = sws[i];
              }
              hashslot = (((oldfactor ^ (oldfactor >> 11)) ^ (oldfactor >> 23)) & 255);
              headslot = ((buildaxis * 256) + hashslot);
              nexts[((buildaxis * cap) + i)] = heads[headslot];
              heads[headslot] = i;
              i = (i + 1);
            }
            buildaxis = (buildaxis + 1);
          }
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
      }
    }
    capture = 0;
    if ((rank < best)) {
      capture = 1;
    }
    if ((rank == best)) {
      if (((step % 64) == 0)) {
        capture = 1;
      }
    }
    if ((capture == 1)) {
      localden = 0;
      t = lane;
      while ((t < rank)) {
        px = sus[t];
        while ((px != 0)) {
          px = (px & (px - 1));
          localden = (localden + 1);
        }
        px = svs[t];
        while ((px != 0)) {
          px = (px & (px - 1));
          localden = (localden + 1);
        }
        px = sws[t];
        while ((px != 0)) {
          px = (px & (px - 1));
          localden = (localden + 1);
        }
        t = (t + 32);
      }
      dsum = simd_sum(localden);
      if ((lane == 0)) {
        capture = 0;
        if ((rank < best)) {
          capture = 1;
        }
        if ((rank == best)) {
          if ((dsum < bestden)) {
            capture = 1;
          }
        }
        if ((capture == 1)) {
          best = rank;
          bestden = dsum;
          captures = (captures + 1);
        }
      }
      capture = simd_broadcast_first(capture);
      best = simd_broadcast_first(best);
      bestden = simd_broadcast_first(bestden);
      captures = simd_broadcast_first(captures);
      if ((capture == 1)) {
        t = lane;
        while ((t < rank)) {
          best_us[(base + t)] = sus[t];
          best_vs[(base + t)] = svs[t];
          best_ws[(base + t)] = sws[t];
          t = (t + 32);
        }
      }
      threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    step = (step + 1);
  }
  i = lane;
  while ((i < rank)) {
    work_us[(base + i)] = sus[i];
    work_vs[(base + i)] = svs[i];
    work_ws[(base + i)] = sws[i];
    i = (i + 32);
  }
  if ((lane == 0)) {
    st[sb] = rank;
    st[(sb + 1)] = best;
    st[(sb + 2)] = state;
    st[(sb + 3)] = bestden;
    st[(sb + 4)] = attempts;
    st[(sb + 5)] = partners;
    st[(sb + 6)] = captures;
    st[(sb + 7)] = 1;
  }
}

