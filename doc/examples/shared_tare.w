# Weigh one sample four times, subtracting the same empty-pan reading.
# Synthetic balance readings in grams; ± gives one standard uncertainty.
use physics

sample = Physics.observable("sample mass", :g)
tare = ~12.00 ± ~0.08
loaded = [~32.02 ± ~0.04, ~31.98 ± ~0.04, ~32.04 ± ~0.04, ~32.00 ± ~0.04]

runs = []
loaded.each ->(reading)
  net = reading - tare
  runs.push(Physics.observation(sample, net, "weighing-[runs.size + 1]"))

shared = Physics.dataset(sample, runs).fit_constant
<< "Accounting for the shared tare: [shared.measurement] g"
<< "Shared-tare fit: chi-square [shared.chi_square] on [shared.degrees_of_freedom] degrees of freedom"
