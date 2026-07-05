# stage0 bootstrap perf log

Each entry is one run of `scripts/bench/stage0-bootstrap.sh [label]`. Labels indicate the configuration / step under test.


## v33-baseline — 2026-05-05T00:33:36Z

- commit: `0fe84a8-dirty`
- env: `SP_GC_DISABLE=` `SP_GC_THRESHOLD=` `SPINEL_EMIT_SYM_SWITCH=`
- stage0 binary: 312032 bytes
- fixtures: PASS (total 0ms)
- missing_fn.w: PASS
- bootstrap: FAIL_RC137 in 666s, hello.ll=0B
- peak RSS @ 60s: 1705552KB; @ 5min: 1705552KB

Sample @ 60s top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Interpreter_visit_call (in tungsten-stage0) 295
     sp_Interpreter_evaluate (in tungsten-stage0) 188
     sp_Interpreter_visit_var (in tungsten-stage0) 173
     _xzm_free (in libsystem_malloc.dylib) 135
     sp_Interpreter_stage0_primitive_call (in tungsten-stage0) 107
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 103
     __vfprintf (in libsystem_c.dylib) 74
     sp_gc_alloc (in tungsten-stage0) 61
     sp_StrPolyHash_set (in tungsten-stage0) 57
```
Sample @ 5min top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Interpreter_visit_call (in tungsten-stage0) 296
     sp_Interpreter_evaluate (in tungsten-stage0) 210
     sp_Interpreter_visit_var (in tungsten-stage0) 185
     _xzm_free (in libsystem_malloc.dylib) 130
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 122
     sp_Interpreter_stage0_primitive_call (in tungsten-stage0) 76
     sp_gc_alloc (in tungsten-stage0) 65
     sp_StrPolyHash_set (in tungsten-stage0) 54
     __vfprintf (in libsystem_c.dylib) 52
```

## step-A-gc-off — 2026-05-05T00:45:29Z

- commit: `0fe84a8-dirty`
- env: `SP_GC_DISABLE=1` `SP_GC_THRESHOLD=` `SPINEL_EMIT_SYM_SWITCH=`
- stage0 binary: 312112 bytes
- fixtures: PASS (total 0ms)
- missing_fn.w: PASS
- bootstrap: FAIL_RC137 in 378s, hello.ll=0B
- peak RSS @ 60s: 73460912KB; @ 5min: 14360496KB

Sample @ 60s top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Interpreter_visit_call (in tungsten-stage0) 282
     sp_Interpreter_evaluate (in tungsten-stage0) 232
     sp_Interpreter_visit_var (in tungsten-stage0) 165
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 136
     sp_Interpreter_stage0_primitive_call (in tungsten-stage0) 101
     _xzm_xzone_thread_cache_fill_and_malloc (in libsystem_malloc.dylib) 99
     sp_StrPolyHash_set (in tungsten-stage0) 72
     sp_Interpreter_visit_binary_op (in tungsten-stage0) 46
     __vfprintf (in libsystem_c.dylib) 39
```
Sample @ 5min top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Interpreter_visit_call (in tungsten-stage0) 283
     sp_Interpreter_evaluate (in tungsten-stage0) 226
     sp_Interpreter_visit_var (in tungsten-stage0) 152
     _xzm_xzone_thread_cache_fill_and_malloc (in libsystem_malloc.dylib) 126
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 117
     sp_Interpreter_stage0_primitive_call (in tungsten-stage0) 117
     sp_StrPolyHash_set (in tungsten-stage0) 71
     sp_Interpreter_visit_binary_op (in tungsten-stage0) 51
     __vfprintf (in libsystem_c.dylib) 38
```

## step-A-thr-4M — 2026-05-05T00:52:12Z

- commit: `0fe84a8-dirty`
- env: `SP_GC_DISABLE=` `SP_GC_THRESHOLD=4194304` `SPINEL_EMIT_SYM_SWITCH=`
- stage0 binary: 312112 bytes
- fixtures: PASS (total 0ms)
- missing_fn.w: PASS
- bootstrap: FAIL_RC137 in 371s, hello.ll=0B
- peak RSS @ 60s: 2027584KB; @ 5min: 2027568KB

Sample @ 60s top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Interpreter_visit_call (in tungsten-stage0) 267
     _xzm_free (in libsystem_malloc.dylib) 232
     sp_Interpreter_evaluate (in tungsten-stage0) 191
     sp_Interpreter_visit_var (in tungsten-stage0) 176
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 97
     sp_Interpreter_stage0_primitive_call (in tungsten-stage0) 80
     sp_gc_alloc (in tungsten-stage0) 80
     sp_StrPolyHash_set (in tungsten-stage0) 78
     __vfprintf (in libsystem_c.dylib) 41
```
Sample @ 5min top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Interpreter_visit_call (in tungsten-stage0) 271
     _xzm_free (in libsystem_malloc.dylib) 229
     sp_Interpreter_evaluate (in tungsten-stage0) 174
     sp_Interpreter_visit_var (in tungsten-stage0) 166
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 101
     sp_Interpreter_stage0_primitive_call (in tungsten-stage0) 86
     sp_gc_alloc (in tungsten-stage0) 71
     sp_StrPolyHash_set (in tungsten-stage0) 57
     sp_Interpreter_visit_binary_op (in tungsten-stage0) 50
```

## step-C-sym-dispatch — 2026-05-05T01:00:21Z

- commit: `0fe84a8-dirty`
- env: `SP_GC_DISABLE=` `SP_GC_THRESHOLD=` `SPINEL_EMIT_SYM_SWITCH=`
- stage0 binary: 311920 bytes
- fixtures: PASS (total 0ms)
- missing_fn.w: PASS
- bootstrap: FAIL_RC137 in 666s, hello.ll=0B
- peak RSS @ 60s: 1701936KB; @ 5min: 1701936KB

Sample @ 60s top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 583
     sp_sym_intern (in tungsten-stage0) 309
     DYLD-STUB$$_platform_strcmp (in libsystem_platform.dylib) 280
     DYLD-STUB$$strcmp (in tungsten-stage0) 238
     sp_Interpreter_visit_call (in tungsten-stage0) 46
     sp_Interpreter_visit_var (in tungsten-stage0) 46
     sp_Interpreter_evaluate (in tungsten-stage0) 40
     _xzm_free (in libsystem_malloc.dylib) 26
     sp_Interpreter_stage0_primitive_call (in tungsten-stage0) 12
```
Sample @ 5min top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 599
     sp_sym_intern (in tungsten-stage0) 289
     DYLD-STUB$$_platform_strcmp (in libsystem_platform.dylib) 284
     DYLD-STUB$$strcmp (in tungsten-stage0) 244
     sp_Interpreter_visit_var (in tungsten-stage0) 50
     sp_Interpreter_evaluate (in tungsten-stage0) 46
     sp_Interpreter_visit_call (in tungsten-stage0) 35
     _xzm_free (in libsystem_malloc.dylib) 27
     __vfprintf (in libsystem_c.dylib) 15
```

## step-C-cached-sym — 2026-05-05T01:15:50Z

- commit: `0fe84a8-dirty`
- env: `SP_GC_DISABLE=` `SP_GC_THRESHOLD=` `SPINEL_EMIT_SYM_SWITCH=`
- stage0 binary: 295232 bytes
- fixtures: PASS (total 1000ms)
- missing_fn.w: PASS
- bootstrap: FAIL_RC137 in 666s, hello.ll=0B
- peak RSS @ 60s: 1690624KB; @ 5min: 1690624KB

Sample @ 60s top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     _xzm_free (in libsystem_malloc.dylib) 294
     sp_Environment_get (in tungsten-stage0) 281
     sp_Interpreter_visit_call (in tungsten-stage0) 213
     sp_gc_alloc (in tungsten-stage0) 156
     sp_Interpreter_evaluate (in tungsten-stage0) 128
     sp_StrPolyHash_set (in tungsten-stage0) 71
     _xzm_xzone_malloc (in libsystem_malloc.dylib) 61
     sp_Interpreter_visit_var (in tungsten-stage0) 61
     _xzm_malloc_zone_malloc_type_calloc_entry (in libsystem_malloc.dylib) 60
```
Sample @ 5min top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Environment_get (in tungsten-stage0) 273
     _xzm_free (in libsystem_malloc.dylib) 270
     sp_Interpreter_visit_call (in tungsten-stage0) 222
     sp_gc_alloc (in tungsten-stage0) 169
     sp_Interpreter_evaluate (in tungsten-stage0) 114
     _xzm_xzone_malloc (in libsystem_malloc.dylib) 70
     sp_StrPolyHash_set (in tungsten-stage0) 68
     _xzm_malloc_zone_malloc_type_calloc_entry (in libsystem_malloc.dylib) 53
     sp_Interpreter_visit_var (in tungsten-stage0) 51
```

## step-C-clean — 2026-05-05T01:46:37Z

- commit: `0fe84a8-dirty`
- env: `SP_GC_DISABLE=` `SP_GC_THRESHOLD=` `SPINEL_EMIT_SYM_SWITCH=`
- stage0 binary: 295232 bytes
- fixtures: PASS (total 0ms)
- missing_fn.w: PASS
- bootstrap: FAIL_RC137 in 666s, hello.ll=0B
- peak RSS @ 60s: 1690448KB; @ 5min: 1690448KB

Sample @ 60s top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     _xzm_free (in libsystem_malloc.dylib) 266
     sp_Environment_get (in tungsten-stage0) 257
     sp_Interpreter_visit_call (in tungsten-stage0) 251
     sp_gc_alloc (in tungsten-stage0) 157
     sp_Interpreter_evaluate (in tungsten-stage0) 133
     _xzm_xzone_malloc (in libsystem_malloc.dylib) 75
     sp_Interpreter_visit_var (in tungsten-stage0) 61
     sp_StrPolyHash_set (in tungsten-stage0) 55
     _xzm_malloc_zone_malloc_type_calloc_entry (in libsystem_malloc.dylib) 50
```
Sample @ 5min top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Environment_get (in tungsten-stage0) 279
     _xzm_free (in libsystem_malloc.dylib) 266
     sp_Interpreter_visit_call (in tungsten-stage0) 239
     sp_gc_alloc (in tungsten-stage0) 151
     sp_Interpreter_evaluate (in tungsten-stage0) 115
     sp_StrPolyHash_set (in tungsten-stage0) 60
     _xzm_malloc_zone_malloc_type_calloc_entry (in libsystem_malloc.dylib) 59
     _xzm_xzone_malloc (in libsystem_malloc.dylib) 59
     _free (in libsystem_malloc.dylib) 53
```

## step-G-lazy-slots — 2026-05-05T03:34:33Z

- commit: `3294389-dirty`
- env: `SP_GC_DISABLE=` `SP_GC_THRESHOLD=` `SPINEL_EMIT_SYM_SWITCH=`
- stage0 binary: 295232 bytes
- fixtures: PASS (total 0ms)
- missing_fn.w: PASS
- bootstrap: FAIL_RC137 in 666s, hello.ll=0B
- peak RSS @ 60s: 1731392KB; @ 5min: 1731376KB

Sample @ 60s top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Environment_get (in tungsten-stage0) 413
     sp_Interpreter_visit_call (in tungsten-stage0) 265
     _xzm_free (in libsystem_malloc.dylib) 174
     sp_Interpreter_evaluate (in tungsten-stage0) 153
     sp_gc_alloc (in tungsten-stage0) 117
     sp_StrPolyHash_set (in tungsten-stage0) 65
     sp_Interpreter_visit_var (in tungsten-stage0) 62
     _xzm_xzone_malloc (in libsystem_malloc.dylib) 53
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 43
```
Sample @ 5min top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Environment_get (in tungsten-stage0) 415
     sp_Interpreter_visit_call (in tungsten-stage0) 248
     _xzm_free (in libsystem_malloc.dylib) 182
     sp_Interpreter_evaluate (in tungsten-stage0) 147
     sp_gc_alloc (in tungsten-stage0) 117
     sp_StrPolyHash_set (in tungsten-stage0) 82
     sp_Interpreter_visit_var (in tungsten-stage0) 65
     _xzm_malloc_zone_malloc_type_calloc_entry (in libsystem_malloc.dylib) 47
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 44
```

## step-G-final — 2026-05-05T03:49:43Z

- commit: `3294389-dirty`
- env: `SP_GC_DISABLE=` `SP_GC_THRESHOLD=` `SPINEL_EMIT_SYM_SWITCH=`
- stage0 binary: 295232 bytes
- fixtures: PASS (total 0ms)
- missing_fn.w: PASS
- bootstrap: FAIL_RC137 in 667s, hello.ll=0B
- peak RSS @ 60s: 1721968KB; @ 5min: 1721968KB

Sample @ 60s top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Environment_get (in tungsten-stage0) 399
     sp_Interpreter_visit_call (in tungsten-stage0) 232
     sp_gc_alloc (in tungsten-stage0) 187
     _xzm_free (in libsystem_malloc.dylib) 180
     sp_Interpreter_evaluate (in tungsten-stage0) 132
     sp_StrPolyHash_set (in tungsten-stage0) 78
     sp_Interpreter_visit_var (in tungsten-stage0) 59
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 43
     _xzm_malloc_zone_malloc_type_calloc_entry (in libsystem_malloc.dylib) 39
```
Sample @ 5min top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Environment_get (in tungsten-stage0) 405
     sp_Interpreter_visit_call (in tungsten-stage0) 254
     _xzm_free (in libsystem_malloc.dylib) 184
     sp_Interpreter_evaluate (in tungsten-stage0) 142
     sp_gc_alloc (in tungsten-stage0) 127
     sp_StrPolyHash_set (in tungsten-stage0) 76
     sp_Interpreter_visit_var (in tungsten-stage0) 54
     _xzm_xzone_malloc (in libsystem_malloc.dylib) 47
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 39
```

## step-H-no-placeholders — 2026-05-05T04:13:30Z

- commit: `cad2f83-dirty`
- env: `SP_GC_DISABLE=` `SP_GC_THRESHOLD=` `SPINEL_EMIT_SYM_SWITCH=`
- stage0 binary: 295232 bytes
- fixtures: PASS (total 0ms)
- missing_fn.w: PASS
- bootstrap: FAIL_RC137 in 666s, hello.ll=0B
- peak RSS @ 60s: 1723488KB; @ 5min: 1723488KB

Sample @ 60s top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Environment_get (in tungsten-stage0) 305
     sp_Interpreter_visit_call (in tungsten-stage0) 300
     _xzm_free (in libsystem_malloc.dylib) 212
     sp_gc_alloc (in tungsten-stage0) 155
     sp_Interpreter_evaluate (in tungsten-stage0) 153
     sp_Interpreter_visit_var (in tungsten-stage0) 56
     _xzm_malloc_zone_malloc_type_calloc_entry (in libsystem_malloc.dylib) 53
     _xzm_xzone_malloc (in libsystem_malloc.dylib) 47
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 45
```
Sample @ 5min top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Environment_get (in tungsten-stage0) 318
     sp_Interpreter_visit_call (in tungsten-stage0) 264
     _xzm_free (in libsystem_malloc.dylib) 203
     sp_Interpreter_evaluate (in tungsten-stage0) 167
     sp_gc_alloc (in tungsten-stage0) 150
     sp_Interpreter_visit_var (in tungsten-stage0) 66
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 49
     _xzm_xzone_malloc (in libsystem_malloc.dylib) 44
     _xzm_malloc_zone_malloc_type_calloc_entry (in libsystem_malloc.dylib) 36
```

## step-I-two-tier — 2026-05-05T04:28:34Z

- commit: `c00d3c6-dirty`
- env: `SP_GC_DISABLE=` `SP_GC_THRESHOLD=` `SPINEL_EMIT_SYM_SWITCH=`
- stage0 binary: 295200 bytes
- fixtures: PASS (total 0ms)
- missing_fn.w: PASS
- bootstrap: FAIL_RC137 in 666s, hello.ll=0B
- peak RSS @ 60s: 1718560KB; @ 5min: 1718560KB

Sample @ 60s top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Interpreter_visit_call (in tungsten-stage0) 365
     _xzm_free (in libsystem_malloc.dylib) 253
     sp_Interpreter_evaluate (in tungsten-stage0) 166
     sp_gc_alloc (in tungsten-stage0) 160
     sp_Interpreter_visit_var (in tungsten-stage0) 105
     _xzm_xzone_malloc (in libsystem_malloc.dylib) 65
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 47
     _xzm_malloc_zone_malloc_type_calloc_entry (in libsystem_malloc.dylib) 46
     _malloc_zone_calloc (in libsystem_malloc.dylib) 42
```
Sample @ 5min top leaves:
```
    Sort by top of stack, same collapsed (when >= 5):
     sp_Interpreter_visit_call (in tungsten-stage0) 370
     _xzm_free (in libsystem_malloc.dylib) 230
     sp_Interpreter_evaluate (in tungsten-stage0) 191
     sp_gc_alloc (in tungsten-stage0) 174
     sp_Interpreter_visit_var (in tungsten-stage0) 93
     _xzm_malloc_zone_malloc_type_calloc_entry (in libsystem_malloc.dylib) 60
     sp_StrPolyHash_set (in tungsten-stage0) 51
     _xzm_xzone_malloc (in libsystem_malloc.dylib) 47
     _platform_strcmp$VARIANT$Base (in libsystem_platform.dylib) 39
```

## step-K-aggressive-flags — 2026-05-05T10:21:56Z

- commit: `f40204b-dirty`
- env: `SP_GC_DISABLE=` `SP_GC_THRESHOLD=` `SPINEL_EMIT_SYM_SWITCH=`
- stage0 binary: 311088 bytes
- fixtures: PASS (total 0ms)
- missing_fn.w: PASS
- bootstrap: FAIL_RC139 in 1s, hello.ll=0B
- peak RSS @ 60s: 0KB; @ 5min: 0KB
