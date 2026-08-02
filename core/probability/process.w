# Executable base protocol for finite-dimensional stochastic process draws.

+ StochasticProcess
  -> sample_path
    raise "sample_path is not implemented for " + self.class_name

  -> finite_dimensional_distribution
    raise ("finite-dimensional distribution is not implemented for " +
           self.class_name)
