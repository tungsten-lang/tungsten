| method | seeds | dims | budget | best @25% (median) | final best: median [min, max] | held-out mean (median) | held-out fails | wall/run s | rollout-s/run | optimizer s/run |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| x0 (start) | - | - | - | -0.271 | -0.271 | -0.500 | 8/8 | - | - | - |
| bo | 6 | 40 | 800 | 0.139 | 0.707 [0.187, 0.910] | -0.486 | 44/48 | 108 | 117 | 48.8 |
| oneplusone | 6 | 40 | 800 | 0.184 | 0.532 [0.164, 0.739] | -0.463 | 47/48 | 76 | 115 | 0.0 |
| cma | 6 | 40 | 800 | -0.138 | 0.087 [-0.172, 0.611] | -0.493 | 48/48 | 67 | 130 | 0.0 |
