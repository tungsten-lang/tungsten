### p1/ease1

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -1.000 | -1.000 | -0.500 | 8/8 | - | - | - |
| cma | 3 | 40 | 800 | -0.109 | -0.069 [-0.099, 0.067] | -0.316 | 24/24 | 63 | 124 | 0.0 |

### p1/ease3

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.500 | -0.500 | -0.500 | 8/8 | - | - | - |
| cma | 3 | 40 | 800 | -0.124 | -0.030 [-0.098, -0.028] | -0.446 | 24/24 | 62 | 121 | 0.0 |

### p1/ease4

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.500 | -0.500 | -0.500 | 8/8 | - | - | - |
| cma | 3 | 40 | 800 | -0.260 | 0.267 [-0.203, 0.435] | -0.485 | 24/24 | 61 | 121 | 0.0 |

### p1/ease7

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.500 | -0.500 | -0.500 | 8/8 | - | - | - |
| cma | 3 | 40 | 800 | -0.449 | 0.211 [-0.402, 0.323] | -0.488 | 24/24 | 63 | 124 | 0.0 |

### p1/ease_search

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.271 | -0.271 | -0.500 | 8/8 | - | - | - |
| cma | 3 | 44 | 800 | -0.016 | 0.289 [0.057, 0.578] | -0.456 | 24/24 | 60 | 118 | 0.0 |

### p1/goal

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.271 | -0.271 | -0.500 | 8/8 | - | - | - |
| bo | 6 | 40 | 800 | 0.139 | 0.707 [0.187, 0.910] | -0.486 | 44/48 | 108 | 117 | 48.8 |
| oneplusone | 6 | 40 | 800 | 0.184 | 0.532 [0.164, 0.739] | -0.463 | 47/48 | 76 | 115 | 0.0 |
| cma | 6 | 40 | 800 | -0.138 | 0.087 [-0.172, 0.611] | -0.493 | 48/48 | 67 | 130 | 0.0 |

### p1/goal_init

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | 0.910 | 0.910 | -0.500 | 8/8 | - | - | - |
| oneplusone | 3 | 40 | 800 | 1.057 | 1.080 [1.038, 1.276] | -0.436 | 22/24 | 66 | 191 | 0.0 |
| bo | 3 | 40 | 800 | 0.992 | 1.071 [1.069, 1.149] | -0.500 | 24/24 | 259 | 626 | 48.1 |

### p1/group

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.271 | -0.271 | -0.500 | 8/8 | - | - | - |
| oneplusone | 3 | 47 | 800 | -0.048 | 0.088 [0.050, 0.125] | -0.460 | 23/24 | 78 | 118 | 0.0 |
| bo | 3 | 47 | 800 | -0.097 | 0.062 [-0.093, 0.191] | -0.500 | 22/24 | 118 | 121 | 55.8 |
| cma | 3 | 47 | 800 | -0.217 | -0.095 [-0.212, -0.091] | -0.327 | 24/24 | 60 | 118 | 0.0 |

### p1/kf

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.271 | -0.271 | -0.500 | 8/8 | - | - | - |
| oneplusone | 6 | 104 | 800 | -0.129 | 0.265 [0.050, 0.825] | -0.500 | 47/48 | 95 | 271 | 0.0 |
| bo | 6 | 104 | 800 | -0.007 | 0.134 [-0.002, 0.250] | -0.500 | 47/48 | 368 | 363 | 108.2 |

### p1/kf_ease

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.271 | -0.271 | -0.500 | 8/8 | - | - | - |
| oneplusone | 3 | 108 | 800 | -0.271 | -0.100 [-0.240, 0.065] | -0.500 | 24/24 | 55 | 159 | 0.0 |

### p1/kf_init

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | 0.910 | 0.910 | -0.500 | 8/8 | - | - | - |
| oneplusone | 3 | 104 | 800 | 1.091 | 1.446 [1.307, 1.522] | -0.480 | 24/24 | 49 | 143 | 0.0 |
| bo | 3 | 104 | 800 | 1.055 | 1.351 [1.137, 1.366] | -0.489 | 24/24 | 170 | 201 | 99.0 |

### p1/kf_linear

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -1.000 | -1.000 | -0.500 | 8/8 | - | - | - |
| oneplusone | 3 | 104 | 800 | -0.176 | -0.049 [-0.210, 0.256] | -0.762 | 24/24 | 479 | 1429 | 0.0 |

### p1/kf_speed

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.271 | -0.271 | -0.500 | 8/8 | - | - | - |
| oneplusone | 3 | 104 | 800 | 0.018 | 0.157 [0.086, 0.825] | -0.464 | 23/24 | 54 | 156 | 0.0 |
| bo | 3 | 104 | 800 | -0.050 | 0.070 [0.061, 1.186] | -0.450 | 18/24 | 184 | 141 | 95.5 |

### p1/kf_syn

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.271 | -0.271 | -0.500 | 8/8 | - | - | - |
| oneplusone | 3 | 32 | 800 | 0.546 | 0.666 [0.183, 0.699] | -0.456 | 22/24 | 1003 | 3004 | 0.0 |
| bo | 3 | 32 | 800 | 0.226 | 0.583 [0.251, 0.832] | -0.447 | 21/24 | 707 | 1038 | 47.2 |

### p1/mrate

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.271 | -0.271 | -0.500 | 8/8 | - | - | - |
| bo | 6 | 64 | 800 | -0.004 | 0.312 [0.073, 0.536] | -0.462 | 43/48 | 121 | 114 | 63.2 |
| oneplusone | 6 | 64 | 800 | -0.121 | 0.007 [-0.169, 0.750] | -0.500 | 48/48 | 75 | 113 | 0.0 |
| cma | 6 | 64 | 800 | -0.257 | -0.022 [-0.140, 0.367] | -0.478 | 46/48 | 57 | 114 | 0.0 |

### p1/rate

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.271 | -0.271 | -0.500 | 8/8 | - | - | - |
| oneplusone | 6 | 40 | 800 | 0.012 | 0.163 [-0.013, 0.500] | -0.500 | 48/48 | 139 | 189 | 0.0 |
| bo | 6 | 40 | 800 | -0.124 | 0.130 [-0.081, 0.304] | -0.464 | 40/48 | 166 | 155 | 61.6 |
| pattern | 3 | 40 | 800 | -0.017 | 0.105 [0.105, 0.105] | -0.500 | 24/24 | 200 | 400 | 0.0 |
| openai_es | 6 | 40 | 800 | 0.070 | 0.070 [-0.073, 0.658] | -0.457 | 46/48 | 102 | 202 | 0.0 |
| sep_cma | 6 | 40 | 800 | -0.270 | 0.027 [-0.171, 0.170] | -0.310 | 48/48 | 107 | 206 | 0.0 |
| cma | 6 | 40 | 800 | -0.176 | 0.009 [-0.242, 0.337] | -0.454 | 44/48 | 108 | 207 | 0.0 |
| ipop | 3 | 40 | 800 | -0.125 | -0.002 [-0.196, 0.045] | -0.499 | 24/24 | 113 | 223 | 0.0 |
| nelder_mead | 3 | 40 | 800 | -0.014 | -0.014 [-0.014, -0.014] | -0.500 | 24/24 | 126 | 249 | 0.0 |
| de | 3 | 40 | 800 | -0.191 | -0.024 [-0.035, -0.015] | -0.440 | 23/24 | 160 | 317 | 0.0 |
| map_elites | 3 | 40 | 800 | -0.128 | -0.043 [-0.128, 0.092] | -0.500 | 24/24 | 133 | 262 | 0.0 |
| ga | 3 | 40 | 800 | -0.191 | -0.085 [-0.108, -0.014] | -0.500 | 24/24 | 190 | 372 | 0.1 |
| cem | 3 | 40 | 800 | -0.271 | -0.109 [-0.133, -0.001] | -0.409 | 21/24 | 150 | 297 | 0.0 |
| random | 3 | 40 | 800 | -0.271 | -0.164 [-0.185, -0.122] | -0.410 | 24/24 | 127 | 252 | 0.0 |

### p1/rate_robust

| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.462 | -0.462 | -0.500 | 8/8 | - | - | - |
| bo | 3 | 40 | 800 | -0.462 | -0.185 [-0.416, -0.168] | -0.377 | 19/24 | 62 | 111 | 5.5 |
| oneplusone | 3 | 40 | 800 | -0.400 | -0.196 [-0.305, -0.093] | -0.317 | 17/24 | 57 | 102 | 0.0 |
| cma | 3 | 40 | 800 | -0.456 | -0.313 [-0.385, -0.166] | -0.444 | 24/24 | 57 | 112 | 0.0 |
