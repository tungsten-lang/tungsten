# Advanced quantity model (compiled Tungsten)

x = 10.0 ± 0.2
<< x

position = (10 m).point(:map)
step = (2 m).delta(:map)
<< position + step

velocity = Tensor<f64, m/s>.zeros([100, 100])
<< velocity.unit
<< velocity.shape

<< (500 nm).equivalent("Hz", :spectral)

## expect stdout
## 10 ± 0.2
## 12 m
## m/s
## [100, 100]
## 599584916000000 Hz
## expect skip compiled-only unit Tensor example
